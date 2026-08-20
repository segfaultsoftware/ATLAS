require "open3"
require "shellwords"

require_relative "deployment"

module Atlas
  class DeploymentAutomation
    CommandError = Deployment::CommandError

    PRODUCTION_REF = "refs/tags/prod"
    STAGING_REF = "refs/tags/staging"
    MAIN_REF = "refs/heads/main"
    PRODUCTION_HOST = "atlas.home.arpa"
    STAGING_HOST = "atlas-staging.home.arpa"
    DEFAULT_PRODUCTION_ROOT = "/srv/apps/ATLAS"
    DEFAULT_STAGING_ROOT = "/srv/apps/ATLAS-staging"
    SHA_PATTERN = /\A[0-9a-f]{7,64}\z/i
    MAX_DIAGNOSTIC_BYTES = 4_096

    class DeploymentAutomationCommandRunner
      MAX_OUTPUT_BYTES = 32_768
      MAX_OUTPUT_LINES = 300
      REMOTE_GIT_SUBCOMMANDS = %w[fetch ls-remote push].freeze
      GIT_OBJECT_ID_PATTERN = /\A[0-9a-f]{40,64}\z/i

      def initialize(secret_values: [], git_auth: nil)
        @secret_values = Array(secret_values).filter_map do |value|
          value = value.to_s
          value unless value.empty?
        end.freeze
        @git_auth = git_auth.to_s unless git_auth.to_s.empty?
      end

      def run(command, environment: {}, chdir: nil)
        puts "$ #{safe_command(command)}"
        stdout, stderr, status = execute(command, environment:, chdir:)
        output = sanitize(stdout + stderr)
        puts output unless output.empty?
        return true if status.success?

        raise CommandError, failure_message(command, status, stderr)
      end

      def capture(command, environment: {}, chdir: nil)
        stdout, stderr, status = execute(command, environment:, chdir:)
        return sanitize(stdout, preserve_git_object_ids: ref_reading_command?(command)) if status.success?

        raise CommandError, failure_message(command, status, stderr)
      end

      private

      attr_reader :secret_values

      def execute(command, environment:, chdir:)
        options = {}
        options[:chdir] = chdir unless chdir.nil?
        stdin, stdout, stderr, wait_thread = Open3.popen3(command_environment(command, environment), *command, **options)
        stdin.close
        outputs = { stdout => +"", stderr => +"" }
        streams = outputs.keys
        output_limit_exceeded = false

        until streams.empty?
          readable = IO.select(streams)&.first || []
          readable.each do |stream|
            begin
              chunk = stream.read_nonblock(16_384)
              next unless chunk.is_a?(String)

              output = outputs.fetch(stream)
              remaining = MAX_OUTPUT_BYTES - output.bytesize
              output << chunk.byteslice(0, remaining) if remaining.positive?
              if chunk.bytesize > remaining && !output_limit_exceeded
                output_limit_exceeded = true
                terminate(wait_thread)
              end
            rescue IO::WaitReadable
              next
            rescue EOFError
              stream.close unless stream.closed?
              streams.delete(stream)
            rescue IOError
              streams.delete(stream)
            end
          end
        end

        status = wait_thread.value
        raise CommandError, "command output exceeded #{MAX_OUTPUT_BYTES} bytes: #{safe_command(command)}" if output_limit_exceeded

        [ normalize_output(outputs.fetch(stdout)), normalize_output(outputs.fetch(stderr)), status ]
      ensure
        stdin.close unless stdin.nil? || stdin.closed?
        [ stdout, stderr ].compact.each { |stream| stream.close unless stream.closed? }
      end

      def failure_message(command, status, stderr)
        message = sanitize(stderr).strip
        detail = message.empty? ? "" : " — #{message}"
        "command failed (#{status.exitstatus}): #{safe_command(command)}#{detail}"
      end

      def command_environment(command, environment)
        return environment unless remote_git_command?(command) && @git_auth

        {
          "GIT_CONFIG_COUNT" => "1",
          "GIT_CONFIG_KEY_0" => "http.https://github.com/.extraheader",
          "GIT_CONFIG_VALUE_0" => @git_auth,
          "GIT_TERMINAL_PROMPT" => "0"
        }.merge(environment)
      end

      def remote_git_command?(command)
        return false unless command.first == "git"

        REMOTE_GIT_SUBCOMMANDS.include?(git_subcommand(command))
      end

      def ref_reading_command?(command)
        return false unless command.first == "git"

        %w[ls-remote rev-parse].include?(git_subcommand(command))
      end

      def git_subcommand(command)
        index = 1
        while command[index] == "-c"
          index += 2
        end
        command[index]
      end

      def terminate(wait_thread)
        Process.kill("TERM", wait_thread.pid)
      rescue Errno::ESRCH
        nil
      end

      def safe_command(command)
        command.map { |argument| sanitize(argument) }.shelljoin
      end

      def bounded_output(value)
        Deployment.bounded_utf8(value, max_bytes: MAX_OUTPUT_BYTES, max_lines: MAX_OUTPUT_LINES)
      end

      def normalize_output(value)
        Deployment.normalize_utf8(value)
      end

      def sanitize(value, preserve_git_object_ids: false)
        sanitized = normalize_output(value)
        secret_values.each { |secret| sanitized.gsub!(secret, "[REDACTED]") }
        sanitized.gsub!(/(Bearer\s+)([^\s]+)/i, "\\1[REDACTED]")
        sanitized.gsub!(/((?:rails[_ -]?master[_ -]?key|password|passwd|secret|token|api[_-]?key|private[_-]?key|credential)\s*[:=]\s*)("(?:\\.|[^"])*"|'(?:\\.|[^'])*'|[^\s,;}\]]+)/i, "\\1[REDACTED]")
        sanitized.gsub!(/((?:authorization|proxy-authorization)\s*[:=]\s*)(?!Bearer\b)("(?:\\.|[^"])*"|'(?:\\.|[^'])*'|[^\s,;}\]]+)/i, "\\1[REDACTED]")
        sanitized.gsub!(/(?<![A-Za-z0-9])[A-Za-z0-9+\/_-]{24,}={0,2}(?![A-Za-z0-9])/) do |value|
          preserve_git_object_ids && GIT_OBJECT_ID_PATTERN.match?(value) ? value : "[REDACTED]"
        end
        bounded_output(sanitized)
      end
    end

    def initialize(
      runner: nil,
      event: ENV,
      secret_values: nil,
      git_auth: nil,
      remote: "origin",
      production_root: ENV.fetch("ATLAS_PRODUCTION_ROOT", DEFAULT_PRODUCTION_ROOT),
      staging_root: ENV.fetch("ATLAS_STAGING_ROOT", DEFAULT_STAGING_ROOT),
      production_host: ENV.fetch("ATLAS_PRODUCTION_HOST", PRODUCTION_HOST),
      staging_host: ENV.fetch("ATLAS_STAGING_HOST", STAGING_HOST),
      deploy_command: %w[bin/deploy update]
    )
      @event = event
      @remote = remote.to_s
      @production_root = production_root.to_s
      @staging_root = staging_root.to_s
      @production_host = production_host.to_s
      @staging_host = staging_host.to_s
      @deploy_command = Array(deploy_command).map(&:to_s).freeze
      @runner = runner || DeploymentAutomationCommandRunner.new(secret_values: secret_values || deployment_secret_values, git_auth:)
    end

    def run
      current_event = normalized_event
      return :ignored unless current_event.fetch(:name) == "push"
      return :ignored if current_event.fetch(:deleted)

      case current_event.fetch(:ref)
      when PRODUCTION_REF
        deploy_production(current_event)
      when MAIN_REF
        advance_and_deploy_staging(current_event)
      when STAGING_REF
        deploy_staging_tag(current_event)
      else
        :ignored
      end
    rescue CommandError => error
      raise CommandError, sanitize(error.message)
    end

    private

    attr_reader :runner, :remote, :production_root, :staging_root,
      :production_host, :staging_host, :deploy_command

    def normalized_event
      event_name = value_from_event("name", "GITHUB_EVENT_NAME")
      ref = value_from_event("ref", "GITHUB_REF")
      before = value_from_event("before", "GITHUB_BEFORE")
      after = value_from_event("after", "GITHUB_SHA")
      deleted = boolean_value(value_from_event("deleted", "GITHUB_REF_DELETED"))

      return { name: event_name, ref:, before:, after:, deleted: } unless event_name == "push" && [ PRODUCTION_REF, MAIN_REF, STAGING_REF ].include?(ref)

      raise ArgumentError, "deployment event name is required" if event_name.to_s.empty?
      raise ArgumentError, "deployment event revision is invalid" unless valid_sha?(after)
      raise ArgumentError, "deployment event previous revision is invalid" unless valid_sha?(before)

      { name: event_name, ref:, before:, after:, deleted: }
    end

    def value_from_event(primary, fallback)
      return event[primary] if event.respond_to?(:key?) && event.key?(primary)
      return event[primary.to_sym] if event.respond_to?(:keys) && event.keys.include?(primary.to_sym)

      event[fallback] if event.respond_to?(:key?) && event.key?(fallback)
    end

    def boolean_value(value)
      %w[1 true].include?(value.to_s.downcase)
    end

    def valid_sha?(value)
      SHA_PATTERN.match?(value.to_s)
    end

    def deploy_production(current_event)
      return :ignored unless remote_revision(PRODUCTION_REF) == current_event.fetch(:after)

      deploy_revision(
        root: production_root,
        revision: current_event.fetch(:after),
        host: production_host,
        before_deploy: -> { ensure_current_production(current_event.fetch(:after)) }
      )
      :production
    end

    def advance_and_deploy_staging(current_event)
      staging_revisions = remote_ref_revisions(STAGING_REF)
      staging_revision = staging_revisions[:peeled] || staging_revisions[:direct]
      return :ignored unless [ current_event.fetch(:before), current_event.fetch(:after) ].include?(staging_revision)

      if staging_revision == current_event.fetch(:before)
        compare_and_swap_staging_ref(current_event, expected_revision: staging_revisions[:direct])
        raise CommandError, "staging ref did not advance to #{current_event.fetch(:after)}" unless remote_revision(STAGING_REF) == current_event.fetch(:after)
      end

      deploy_staging_revision(current_event.fetch(:after))
      :staging
    end

    def deploy_staging_tag(current_event)
      return :ignored unless remote_revision(STAGING_REF) == current_event.fetch(:after)

      deploy_staging_revision(current_event.fetch(:after))
      :staging
    end

    def deploy_staging_revision(revision)
      deploy_revision(
        root: staging_root,
        revision:,
        host: staging_host,
        before_checkout: -> { ensure_current_staging(revision) },
        before_deploy: -> { ensure_current_staging(revision) }
      )
    end

    def remote_revision(ref)
      revisions = remote_ref_revisions(ref)
      revisions[:peeled] || revisions[:direct]
    end

    def remote_ref_revisions(ref)
      output = capture(git_command("ls-remote", remote, ref, "#{ref}^{}"))
      revisions = output.to_s.lines.filter_map do |line|
        revision, returned_ref = line.split(/\s+/, 2)
        next unless revision && returned_ref

        [ returned_ref.strip, revision ]
      end.to_h

      { direct: revisions[ref], peeled: revisions["#{ref}^{}"] }
    end

    def compare_and_swap_staging_ref(current_event, expected_revision:)
      after = current_event.fetch(:after)
      execute(
        git_command(
          "push", remote, "#{after}:#{STAGING_REF}",
          "--force-with-lease=#{STAGING_REF}:#{expected_revision}"
        )
      )
    end

    def deploy_revision(root:, revision:, host:, before_checkout: nil, before_deploy: nil)
      status = capture(
        git_command("status", "--porcelain=v1", "--ignored", "--untracked-files=normal", "--", ".", ":(exclude)storage"),
        chdir: root
      )
      visible_changes = status.to_s.lines.reject { |line| line.start_with?("!! ") }
      unless visible_changes.empty?
        raise CommandError, "deployment checkout is not clean: #{bounded_diagnostic(visible_changes.join)}"
      end
      unexpected_ignored = status.to_s.lines.filter_map do |line|
        next unless line.start_with?("!! ")

        path = line.delete_prefix("!! ").strip
        next if path == ".env"

        path
      end
      unless unexpected_ignored.empty?
        raise CommandError, "deployment checkout contains unapproved ignored files: #{bounded_diagnostic(unexpected_ignored.join)}"
      end

      execute(git_command("fetch", "--no-tags", remote, revision), chdir: root)
      before_checkout&.call
      execute(git_command("checkout", "--detach", "--force", revision), chdir: root)
      before_deploy&.call
      environment = { "ATLAS_HOST" => host }
      execute(deploy_command, environment:, chdir: root)
    end

    def execute(command, environment: {}, chdir: nil)
      return runner.run(command) if environment.empty? && chdir.nil?

      runner.run(command, environment:, chdir:)
    end

    def git_command(subcommand, *arguments)
      [ "git", "-c", "core.hooksPath=/dev/null", subcommand, *arguments ]
    end

    def capture(command, environment: {}, chdir: nil)
      return runner.capture(command) if environment.empty? && chdir.nil?

      runner.capture(command, environment:, chdir:)
    end

    def sanitize(value)
      value.to_s
        .gsub(/(Bearer\s+)([^\s]+)/i, "\\1[REDACTED]")
        .gsub(/((?:rails[_ -]?master[_ -]?key|password|passwd|secret|token|api[_-]?key|private[_-]?key|credential)\s*[:=]\s*)("(?:\\.|[^"])*"|'(?:\\.|[^'])*'|[^\s,;}\]]+)/i, "\\1[REDACTED]")
        .gsub(/((?:authorization|proxy-authorization)\s*[:=]\s*)(?!Bearer\b)("(?:\\.|[^"])*"|'(?:\\.|[^'])*'|[^\s,;}\]]+)/i, "\\1[REDACTED]")
        .gsub(/(?<![A-Za-z0-9])[A-Za-z0-9+\/_-]{24,}={0,2}(?![A-Za-z0-9])/, "[REDACTED]")
        .lines.first(40).join.byteslice(0, MAX_DIAGNOSTIC_BYTES).to_s.scrub
    end

    def bounded_diagnostic(value)
      value.to_s.lines.first(20).join.byteslice(0, 1_024).to_s.scrub
    end

    def ensure_current_production(revision)
      return if remote_revision(PRODUCTION_REF) == revision

      raise CommandError, "prod ref changed before deployment; refusing revision #{revision}"
    end

    def ensure_current_staging(revision)
      return if remote_revision(STAGING_REF) == revision

      raise CommandError, "staging ref changed before deployment; refusing revision #{revision}"
    end

    def deployment_secret_values
      values = [ value_from_event("rails_master_key", "RAILS_MASTER_KEY") ]
      secret_files = [ value_from_event("rails_master_key_file", "RAILS_MASTER_KEY_FILE") ]
      [ production_root, staging_root ].each do |root|
        dotenv_path = File.join(root, ".env")
        next unless File.file?(dotenv_path)

        File.foreach(dotenv_path) do |line|
          match = /\A(RAILS_MASTER_KEY(?:_FILE)?)=(.*)\z/.match(line.strip)
          next unless match

          value = match[2].strip
          value = value[1..-2] if value.length >= 2 && value.start_with?("\"", "'") && value.end_with?(value[0])
          if match[1] == "RAILS_MASTER_KEY_FILE"
            secret_files << File.expand_path(value, root)
          else
            values << value
          end
        end
      end
      secret_files << Deployment::DeployWorkflow::DEFAULT_RAILS_MASTER_KEY_FILE
      secret_files.compact.uniq.each do |secret_file|
        values << File.read(secret_file).strip if File.file?(secret_file)
      end
      values.compact.reject(&:empty?).uniq
    rescue Errno::EACCES, Errno::EISDIR, Errno::ENOENT
      values.compact.reject(&:empty?).uniq
    end

    attr_reader :event
  end
end
