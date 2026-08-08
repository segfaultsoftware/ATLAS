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
    DEFAULT_HOSTS = { production: "atlas.home.arpa", staging: "atlas-staging.home.arpa" }.freeze
    SHA = /\A[0-9a-f]{40}\z/i
    ZERO_SHA = "0" * 40

    Event = Struct.new(:name, :ref, :before, :after, :deleted, :created, :forced, keyword_init: true)
    RemoteRef = Struct.new(:revision, :lease_revision, keyword_init: true)

    class CommandError < StandardError; end

    class CommandRunner
      def run(command, chdir:, environment: {})
        system(environment, *command, chdir:, exception: true)
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
        diagnostic = DeploymentAutomation.send(:sanitize_diagnostic, details)
        "command failed: #{command.shelljoin}#{diagnostic.empty? ? "" : " — #{diagnostic}"}"
      end
    end

    def self.event_from_environment(env: ENV, event_path: env["GITHUB_EVENT_PATH"])
      payload = load_event_payload(event_path)
      payload_ref = payload["ref"].to_s
      configured_ref = env["GITHUB_REF"].to_s
      if !configured_ref.empty? && !payload_ref.empty? && configured_ref != payload_ref
        raise CommandError, "GitHub event ref does not match GITHUB_REF"
      end

      Event.new(
        name: env.fetch("GITHUB_EVENT_NAME", "").to_s,
        ref: configured_ref.empty? ? payload_ref : configured_ref,
        before: payload["before"].to_s,
        after: payload.fetch("after", env["GITHUB_SHA"]).to_s,
        deleted: payload["deleted"] == true,
        created: payload["created"] == true,
        forced: payload["forced"] == true
      )
    rescue JSON::ParserError => error
      raise CommandError, "invalid GitHub event payload: #{error.message}"
    end

    def self.load_event_payload(event_path)
      return {} unless event_path && File.file?(event_path)

      payload = JSON.parse(File.read(event_path))
      raise CommandError, "GitHub event payload must be an object" unless payload.is_a?(Hash)

      payload
    end
    private_class_method :load_event_payload

    def self.sanitize_diagnostic(value)
      sanitized = value.to_s.dup
      sanitized.gsub!(%r{https?://[^\s/@]+:[^\s/@]+@}, "https://[REDACTED]@")
      sanitized.gsub!(/(?<prefix>\b(?:token|password|passwd|secret|key|credential|authorization)\b\s*[:=]\s*)(?<value>[^\s,;]+)/i) do
        "#{Regexp.last_match[:prefix]}[REDACTED]"
      end
      sanitized.lines.first(20).join.byteslice(0, 4_096).to_s.scrub
    end
    private_class_method :sanitize_diagnostic

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
      @environment = env
    end

    def run
      return result(status: :noop, reason: :unsupported_event) unless event.name == "push"
      return result(status: :noop, reason: :unrelated_ref) unless [ PRODUCTION_REF, MAIN_REF ].include?(event.ref)
      return result(status: :noop, reason: :deleted_ref) if event.deleted

      validate_revision!(event.after, "after")
      event.ref == PRODUCTION_REF ? deploy_production : deploy_staging
    rescue CommandError => error
      raise CommandError, self.class.send(:sanitize_diagnostic, error.message)
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
      return result(status: :noop, reason: :stale_main_event) unless current_main&.revision == event.after

      if current_staging.revision == event.after
        return deploy(path: staging_path, environment: :staging, revision: event.after)
      end

      return result(status: :noop, reason: :staging_pinned) unless current_staging.revision == event.before

      ensure_clean_checkout(staging_path)
      update_staging_tag(expected_revision: current_staging.lease_revision)
      updated_staging = remote_ref(staging_path, STAGING_REF)
      unless updated_staging&.revision == event.after
        raise CommandError, "staging tag update could not be verified"
      end

      deploy(path: staging_path, environment: :staging, revision: event.after)
    end

    def update_staging_tag(expected_revision:)
      run_command(
        [
          "git", "push", "--force-with-lease=#{STAGING_REF}:#{expected_revision}",
          remote, "#{event.after}:#{STAGING_REF}"
        ],
        chdir: staging_path
      )
    end

    def deploy(path:, environment:, revision:)
      synchronize_checkout(path, revision)
      run_command([ "bin/deploy", "update" ], chdir: path, environment: target_environment(environment))
      run_command([ "bin/verify-deployment" ], chdir: path, environment: target_environment(environment))
      result(status: :deployed, environment:, revision:)
    end

    def synchronize_checkout(path, revision)
      ensure_clean_checkout(path)
      git_run(path, "fetch", "--no-tags", remote, revision)
      git_run(path, "checkout", "--detach", "--force", revision)
      actual_revision = git_capture(path, "rev-parse", "HEAD").strip
      raise CommandError, "deployment checkout revision mismatch" unless actual_revision == revision
    end

    def ensure_clean_checkout(path)
      unless path.directory? && path.join(".git").exist?
        raise CommandError, "deployment checkout is unavailable: #{path}"
      end

      status = git_capture(path, "status", "--porcelain=v1", "--untracked-files=all")
      return if status.strip.empty?

      raise CommandError, "deployment checkout working tree is not clean: #{path}"
    end

    def remote_ref(path, ref)
      arguments = [ "ls-remote", remote, ref ]
      arguments << "#{ref}^{}" if ref.start_with?("refs/tags/")
      output = git_capture(path, *arguments)
      entries = output.lines.filter_map do |line|
        sha, remote_ref_name = line.split(/\s+/, 2)
        next unless sha && remote_ref_name

        [ sha, remote_ref_name.strip ]
      end
      return if entries.empty?

      entry = entries.find { |sha, name| name == "#{ref}^{}" } || entries.find { |sha, name| name == ref }
      raise CommandError, "remote ref has an invalid revision: #{ref}" unless entry&.first&.match?(SHA)

      lease_entry = entries.find { |sha, name| name == ref } || entry
      raise CommandError, "remote ref has an invalid lease revision: #{ref}" unless lease_entry.first.match?(SHA)

      RemoteRef.new(revision: entry.first, lease_revision: lease_entry.first)
    end

    def git_capture(path, *arguments)
      capture_command([ "git", *arguments ], chdir: path)
    end

    def git_run(path, *arguments)
      run_command([ "git", *arguments ], chdir: path)
    end

    def capture_command(command, chdir:)
      runner.capture(command, chdir: chdir.to_s)
    rescue StandardError => error
      raise CommandError, self.class.send(:sanitize_diagnostic, error.message)
    end

    def run_command(command, chdir:, environment: {})
      if environment.empty?
        runner.run(command, chdir: chdir.to_s)
      else
        runner.run(command, chdir: chdir.to_s, environment:)
      end
    rescue StandardError => error
      raise CommandError, self.class.send(:sanitize_diagnostic, error.message)
    end

    def validate_revision!(revision, name)
      unless revision.to_s.match?(SHA) && revision != ZERO_SHA
        raise CommandError, "GitHub event #{name} revision is invalid"
      end
    end

    def target_environment(environment)
      { "ATLAS_HOST" => @environment.fetch("ATLAS_#{environment.to_s.upcase}_HOST", DEFAULT_HOSTS.fetch(environment)) }
    end

    def result(**values)
      values
    end
  end
end
