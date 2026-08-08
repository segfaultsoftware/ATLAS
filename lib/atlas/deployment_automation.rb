require "json"
require "open3"
require "pathname"
require "shellwords"

module Atlas
  class DeploymentAutomation
    PRODUCTION_REF = "refs/tags/prod"
    STAGING_REF = "refs/tags/staging"
    MAIN_REF = "refs/heads/main"
    PRODUCTION_CHECKOUT = "/srv/apps/ATLAS"
    STAGING_CHECKOUT = "/srv/apps/ATLAS-staging"
    SHA = /\A[0-9a-f]{40}\z/i
    ZERO_SHA = "0" * 40

    Event = Struct.new(
      :name,
      :ref,
      :before,
      :after,
      :deleted,
      :created,
      :forced,
      keyword_init: true
    )
    RemoteRef = Struct.new(:revision, :lease_revision, keyword_init: true)

    class CommandError < StandardError; end

    class CommandRunner
      def run(command, chdir:)
        system(*command, chdir:, exception: true)
        true
      rescue StandardError => error
        raise CommandError, failure_message(command, error.message)
      end

      def capture(command, chdir:)
        stdout, stderr, status = Open3.capture3(*command, chdir:)
        return stdout if status.success?

        raise CommandError, failure_message(command, stderr)
      rescue CommandError
        raise
      rescue StandardError => error
        raise CommandError, failure_message(command, error.message)
      end

      private

      def failure_message(command, details)
        sanitized = details.to_s.gsub(%r{https?://[^\s/@]+:[^\s/@]+@}, "https://[REDACTED]@")
        "command failed: #{command.shelljoin}#{sanitized.empty? ? "" : " — #{sanitized.lines.first(20).join.byteslice(0, 4_096)}"}"
      end
    end

    def self.event_from_environment(env: ENV, event_path: env["GITHUB_EVENT_PATH"])
      payload = load_event_payload(event_path)
      if env["GITHUB_REF"] && payload["ref"] && env["GITHUB_REF"] != payload["ref"]
        raise CommandError, "GitHub event ref does not match GITHUB_REF"
      end

      Event.new(
        name: env["GITHUB_EVENT_NAME"].to_s,
        ref: env["GITHUB_REF"] || payload["ref"].to_s,
        before: payload["before"].to_s,
        after: payload["after"] || env["GITHUB_SHA"],
        deleted: payload["deleted"] == true,
        created: payload["created"] == true,
        forced: payload["forced"] == true
      )
    rescue JSON::ParserError => error
      raise CommandError, "invalid GitHub event payload: #{error.message}"
    end

    def self.load_event_payload(event_path)
      return {} unless event_path && File.file?(event_path)

      JSON.parse(File.read(event_path))
    end
    private_class_method :load_event_payload

    def initialize(
      event: nil,
      runner: CommandRunner.new,
      env: ENV,
      production_path: nil,
      staging_path: nil,
      remote: "origin"
    )
      @event = event || self.class.event_from_environment(env:)
      @runner = runner
      @production_path = Pathname(production_path || env.fetch("ATLAS_PRODUCTION_CHECKOUT", PRODUCTION_CHECKOUT))
      @staging_path = Pathname(staging_path || env.fetch("ATLAS_STAGING_CHECKOUT", STAGING_CHECKOUT))
      @remote = remote
    end

    def run
      return result(status: :noop, reason: :unsupported_event) unless event.name == "push"
      return result(status: :noop, reason: :unrelated_ref) unless [ PRODUCTION_REF, MAIN_REF ].include?(event.ref)
      return result(status: :noop, reason: :deleted_ref) if event.deleted

      validate_revision!(event.after, "after")
      return deploy_production if event.ref == PRODUCTION_REF

      deploy_staging
    end

    private

    attr_reader :event, :runner, :production_path, :staging_path, :remote

    def deploy_production
      current_ref = remote_ref(production_path, PRODUCTION_REF)
      unless current_ref&.revision == event.after
        raise CommandError, "remote prod tag does not identify the event revision"
      end

      deploy(path: production_path, environment: :production, revision: event.after)
    end

    def deploy_staging
      validate_revision!(event.before, "before")
      raise CommandError, "main event has no revision change" if event.before == event.after

      current_staging = remote_ref(staging_path, STAGING_REF)
      return result(status: :noop, reason: :staging_tag_absent) unless current_staging

      current_main = remote_ref(staging_path, MAIN_REF)
      raise CommandError, "remote main ref is unavailable" unless current_main
      return result(status: :noop, reason: :stale_main_event) unless current_main.revision == event.after

      if current_staging.revision == event.after
        return deploy(path: staging_path, environment: :staging, revision: event.after)
      end

      return result(status: :noop, reason: :staging_pinned) unless current_staging.revision == event.before

      ensure_clean_checkout(staging_path)
      update_staging_tag(expected_revision: current_staging.lease_revision)
      updated_staging = remote_ref(staging_path, STAGING_REF)
      raise CommandError, "staging tag update could not be verified" unless updated_staging&.revision == event.after

      deploy(path: staging_path, environment: :staging, revision: event.after)
    end

    def update_staging_tag(expected_revision:)
      runner.run(
        [
          "git", "push", "--force-with-lease=#{STAGING_REF}:#{expected_revision}",
          remote, "#{event.after}:#{STAGING_REF}"
        ],
        chdir: staging_path.to_s
      )
    end

    def deploy(path:, environment:, revision:)
      synchronize_checkout(path, revision)
      runner.run([ "bin/deploy", "update" ], chdir: path.to_s)
      runner.run([ "bin/verify-deployment" ], chdir: path.to_s)
      result(status: :deployed, environment:, revision:)
    end

    def synchronize_checkout(path, revision)
      ensure_clean_checkout(path)

      git_run(path, "fetch", "--no-tags", remote, revision)
      git_run(path, "checkout", "--detach", revision)
      actual_revision = git_capture(path, "rev-parse", "HEAD").strip
      raise CommandError, "deployment checkout revision mismatch" unless actual_revision == revision
    end

    def ensure_clean_checkout(path)
      unless path.directory? && path.join(".git").exist?
        raise CommandError, "deployment checkout is unavailable: #{path}"
      end

      status = git_capture(path, "status", "--porcelain=v1", "--untracked-files=all")
      raise CommandError, "deployment checkout working tree is not clean: #{path}" unless status.strip.empty?
    end

    def remote_ref(path, ref)
      ref_arguments = [ "ls-remote", remote, ref ]
      ref_arguments << "#{ref}^{}" if ref.start_with?("refs/tags/")
      output = git_capture(path, *ref_arguments)
      entries = output.lines.filter_map do |line|
        sha, remote_ref = line.split(/\s+/, 2)
        [ sha, remote_ref.strip ] if sha && remote_ref
      end

      entry = entries.find { |sha, remote_ref| remote_ref == "#{ref}^{}" } || entries.find { |sha, remote_ref| remote_ref == ref }
      return unless entry

      revision = entry.first
      raise CommandError, "remote ref has an invalid revision: #{ref}" unless revision.match?(SHA)

      RemoteRef.new(
        revision:,
        lease_revision: (entries.find { |sha, remote_ref| remote_ref == ref } || entry).first
      )
    end

    def git_capture(path, *arguments)
      runner.capture([ "git", *arguments ], chdir: path.to_s)
    end

    def git_run(path, *arguments)
      runner.run([ "git", *arguments ], chdir: path.to_s)
    end

    def validate_revision!(revision, name)
      unless revision.to_s.match?(SHA) && revision != ZERO_SHA
        raise CommandError, "GitHub event #{name} revision is invalid"
      end
    end

    def result(**values)
      values
    end
  end
end
