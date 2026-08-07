require "json"
require "open3"
require "pathname"
require "shellwords"
require "uri"

module Atlas
  module Deployment
    SERVICE = "atlas"
    COMPOSE = %w[docker compose].freeze
    class CommandError < StandardError; end

    class CommandRunner
      def run(command)
        puts "$ #{command.shelljoin}"
        system(*command, exception: true)
      end

      def capture(command)
        stdout, stderr, status = Open3.capture3(*command)
        return stdout if status.success?

        message = stderr.to_s.strip
        raise CommandError, "command failed (#{status.exitstatus}): #{command.shelljoin}#{message.empty? ? "" : " — #{message}"}"
      end

      def capture_bounded(command, max_bytes:, max_lines:)
        raise ArgumentError, "max bytes must be positive" unless max_bytes.to_i.positive?
        raise ArgumentError, "max lines must be positive" unless max_lines.to_i.positive?

        stdin, stdout, stderr, wait_thread = Open3.popen3(*command)
        stdin.close
        outputs = { stdout => +"", stderr => +"" }
        streams = outputs.keys

        until streams.empty?
          readable = IO.select(streams)&.first || []
          readable.each do |stream|
            begin
              chunk = stream.read_nonblock(16_384)
              next unless chunk.is_a?(String)

              output = outputs.fetch(stream)
              remaining = max_bytes - output.bytesize
              output << chunk.byteslice(0, remaining) if remaining.positive?
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
        return bounded_output(outputs.fetch(stdout), max_bytes:, max_lines:) if status.success?

        message = bounded_output(outputs.fetch(stderr), max_bytes:, max_lines:).strip
        raise CommandError, "command failed (#{status.exitstatus}): #{command.shelljoin}#{message.empty? ? "" : " — #{message}"}"
      ensure
        stdin.close unless stdin.nil? || stdin.closed?
        [ stdout, stderr ].compact.each { |stream| stream.close unless stream.closed? }
      end

      private

      def bounded_output(value, max_bytes:, max_lines:)
        value.to_s.lines.first(max_lines).join.byteslice(0, max_bytes).to_s.scrub
      end
    end

    class ReadinessWaiter
      DEFAULT_TIMEOUT = 120
      DEFAULT_POLL_INTERVAL = 2
      MAX_LOG_LINES = 200
      MAX_STATUS_LINES = 20
      MAX_STATUS_BYTES = 4_096
      MAX_STATUS_VALUE_BYTES = 1_024
      MAX_HEALTH_LINES = 50
      MAX_HEALTH_BYTES = 8_192
      MAX_LOG_BYTES = 16_384
      MAX_ERROR_LINES = 20
      MAX_ERROR_BYTES = 4_096
      MAX_FAILURE_LINES = 300
      MAX_FAILURE_BYTES = 32_768
      STATUS_FIELDS = %w[ID Service State Health Status ExitCode].freeze
      REDACTION = "[REDACTED]"
      SENSITIVE_KEY = /(?:rails[_ -]?master[_ -]?key|password|passwd|secret(?:[_ -]?key(?:[_ -]?base)?|[_ -]?base)?|token|api[_ -]?key|access[_ -]?key|private[_ -]?key|credential|authorization)/i
      SENSITIVE_BLOCK = /(?<prefix>["']?#{SENSITIVE_KEY}["']?[ \t]*[:=][ \t]*)(?<value>\|[ \t]*\r?\n(?:[ \t]+[^\r\n]*(?:\r?\n|$))*)/im
      SENSITIVE_ASSIGNMENT = /(?<prefix>["']?#{SENSITIVE_KEY}["']?[ \t]*[:=][ \t]*)(?<value>"(?:\\.|[^"])*"|'(?:\\.|[^'])*'|[^\s,;}\]\r\n]+)/im
      BEARER_VALUE = /(?<prefix>\b(?:authorization|proxy-authorization)[ \t]*[:=][ \t]*Bearer[ \t]+)(?<value>[^\s\r\n]+)/i
      PEM_VALUE = /-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----/im

      def initialize(
        runner: CommandRunner.new,
        timeout: DEFAULT_TIMEOUT,
        poll_interval: DEFAULT_POLL_INTERVAL,
        clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
        sleeper: ->(duration) { sleep(duration) },
        secret_values: []
      )
        raise ArgumentError, "timeout must be non-negative" if timeout.to_f.negative?
        raise ArgumentError, "poll interval must be positive" unless poll_interval.to_f.positive?

        @runner = runner
        @timeout = timeout
        @poll_interval = poll_interval
        @clock = clock
        @sleeper = sleeper
        @secret_values = Array(secret_values).filter_map do |value|
          value = value.to_s
          value unless value.empty?
        end.freeze
      end

      def wait
        deadline = clock.call + timeout
        latest_status = nil
        status_error = nil

        loop do
          begin
            latest_status = parse_status(capture_bounded(status_command, lines: MAX_STATUS_LINES, bytes: MAX_STATUS_BYTES))
            status_error = nil
          rescue CommandError => error
            latest_status = nil
            status_error = error
          end

          case readiness_state(latest_status)
          when :ready
            return true
          when :unhealthy, :exited
            raise failure(readiness_state(latest_status), latest_status, status_error)
          end

          remaining = deadline - clock.call
          break if remaining <= 0

          sleeper.call([ poll_interval, remaining ].min)
        end

        raise failure(:timeout, latest_status, status_error)
      end

      private

      attr_reader :runner, :timeout, :poll_interval, :clock, :sleeper, :secret_values

      def status_command
        COMPOSE + [ "ps", "--format", "json", "--all", SERVICE ]
      end

      def logs_command
        COMPOSE + [ "logs", "--no-color", "--tail", MAX_LOG_LINES.to_s, SERVICE ]
      end

      def inspect_command(container_id)
        [ "docker", "inspect", "--format", "{{json .State.Health}}", container_id ]
      end

      def parse_status(output)
        records = output.to_s.lines.filter_map do |line|
          next if line.strip.empty?

          parsed = JSON.parse(line)
          parsed.is_a?(Array) ? parsed : [ parsed ]
        end.flatten
        return if records.empty?

        records.find { |record| record.is_a?(Hash) && record["Service"].to_s == SERVICE } || records.first
      rescue JSON::ParserError => error
        raise CommandError, "invalid Compose status JSON: #{error.message}"
      end

      def readiness_state(status)
        return :unavailable unless status.is_a?(Hash)

        state = status["State"].to_s.downcase
        health = status["Health"].to_s.downcase
        return :ready if state == "running" && health == "healthy"
        return :unhealthy if health == "unhealthy"
        return :exited if %w[exited dead].include?(state)

        :waiting
      end

      def failure(reason, status, status_error)
        reason_label = reason == :timeout ? "timed out" : reason
        details = [ "reason=#{reason_label}" ]
        details << "status=#{status_summary(status)}" if status
        details << "status_error=#{bounded_diagnostic(status_error.message, lines: MAX_ERROR_LINES, bytes: MAX_ERROR_BYTES)}" if status_error
        details << "health=#{health_detail(status)}" if status
        details << "logs=#{logs_detail}"
        CommandError.new(
          bounded_diagnostic(
            "Compose readiness failed: #{details.join("; ")}",
            lines: MAX_FAILURE_LINES,
            bytes: MAX_FAILURE_BYTES
          )
        )
      end

      def status_summary(status)
        summary = STATUS_FIELDS.filter_map do |field|
          value = status[field]
          next if value.nil?

          "#{field}=#{bounded_diagnostic(value, lines: 1, bytes: MAX_STATUS_VALUE_BYTES)}"
        end.join(", ")
        bounded_diagnostic(summary, lines: MAX_STATUS_LINES, bytes: MAX_STATUS_BYTES)
      end

      def health_detail(status)
        container_id = status["ID"].to_s
        return bounded_diagnostic(status["Health"], lines: MAX_HEALTH_LINES, bytes: MAX_HEALTH_BYTES) unless container_id != ""

        bounded_diagnostic(capture_bounded(inspect_command(container_id), lines: MAX_HEALTH_LINES, bytes: MAX_HEALTH_BYTES), lines: MAX_HEALTH_LINES, bytes: MAX_HEALTH_BYTES)
      rescue CommandError => error
        detail = status["Health"].to_s.empty? ? "unavailable (#{error.message})" : status["Health"]
        bounded_diagnostic(detail, lines: MAX_HEALTH_LINES, bytes: MAX_HEALTH_BYTES)
      end

      def logs_detail
        bounded_diagnostic(capture_bounded(logs_command, lines: MAX_LOG_LINES, bytes: MAX_LOG_BYTES), lines: MAX_LOG_LINES, bytes: MAX_LOG_BYTES)
      rescue CommandError => error
        bounded_diagnostic("unavailable (#{error.message})", lines: MAX_LOG_LINES, bytes: MAX_LOG_BYTES)
      end

      def bounded_diagnostic(value, lines:, bytes:)
        sanitized = sanitize(value)
        sanitized.lines.first(lines).join.byteslice(0, bytes).to_s.scrub
      end

      def capture_bounded(command, lines:, bytes:)
        if runner.respond_to?(:capture_bounded)
          runner.capture_bounded(command, max_bytes: bytes, max_lines: lines)
        else
          runner.capture(command)
        end
      end

      def sanitize(value)
        sanitized = value.to_s.dup
        secret_values.each { |secret| sanitized.gsub!(secret, REDACTION) }
        sanitized.gsub!(PEM_VALUE, REDACTION)
        sanitized.gsub!(SENSITIVE_BLOCK) { "#{Regexp.last_match[:prefix]}#{REDACTION}" }
        sanitized.gsub!(BEARER_VALUE) { "#{Regexp.last_match[:prefix]}#{REDACTION}" }
        sanitized.gsub!(SENSITIVE_ASSIGNMENT) { "#{Regexp.last_match[:prefix]}#{REDACTION}" }
        sanitized
      end
    end

    class Verifier
      def initialize(runner: CommandRunner.new, repository_root: Pathname(__dir__).join("../..").expand_path, env: ENV)
        @runner = runner
        @repository_root = Pathname(repository_root)
        @env = env
      end

      def verify
        @runner.run(compose("config", "--quiet"))
        verify_running_service
        verify_no_published_ports
        verify_endpoint("/up")
        verify_endpoint("/status")
        verify_secret_hygiene
        true
      end

      private

      attr_reader :runner, :repository_root, :env

      def compose(*arguments)
        COMPOSE + arguments
      end

      def verify_running_service
        services = runner.capture(compose("ps", "--status", "running", "--services"))
        return if services.lines.map(&:strip).include?(SERVICE)

        raise CommandError, "Compose service #{SERVICE.inspect} is not running"
      end

      def verify_no_published_ports
        rendered_config = JSON.parse(runner.capture(compose("config", "--format", "json")))
        service = rendered_config.fetch("services").fetch(SERVICE)
        published_mapping = Array(service["ports"]).find do |mapping|
          mapping.is_a?(Hash) && mapping["target"].to_i == 80 && !mapping["published"].nil?
        end
        return if published_mapping.nil?

        raise CommandError, "Compose published an unexpected host port for #{SERVICE}: #{published_mapping.fetch("published")}"
      end

      def verify_endpoint(path)
        runner.capture([
          "curl", "--fail", "--silent", "--show-error", "--location",
          "--header", "Host: #{host}", "#{base_url}#{path}"
        ])
      end

      def verify_secret_hygiene
        verify_dockerignore
        secret_value = env.fetch("RAILS_MASTER_KEY", "").strip
        secret_value = runner.capture(compose("exec", "--no-TTY", SERVICE, "sh", "-c", "cat /run/secrets/rails_master_key")).strip if secret_value.empty?
        raise CommandError, "could not read the Rails master key from the running service" if secret_value.empty?
        rendered_config = runner.capture(compose("config"))
        raise CommandError, "rendered Compose configuration contains the Rails master key" if rendered_config.include?(secret_value)

        tracked_files = runner.capture(%w[git ls-files -z]).split("\0").reject(&:empty?)
        tracked_files.each do |relative_path|
          next unless (path = repository_root.join(relative_path)).file?
          next unless path.open("rb") { |file| file.each_line.any? { |line| line.include?(secret_value) } }

          raise CommandError, "tracked file contains the Rails master key: #{relative_path}"
        end

        image = runner.capture(compose("images", "-q", SERVICE)).strip
        return if image.empty?

        history = runner.capture([ "docker", "history", "--no-trunc", image ])
        raise CommandError, "Docker image history contains the Rails master key" if history.include?(secret_value)

        logs = runner.capture(compose("logs", "--no-color", "--tail", "1000", SERVICE))
        raise CommandError, "container logs contain the Rails master key" if logs.include?(secret_value)
      end

      def verify_dockerignore
        dockerignore = repository_root.join(".dockerignore").read
        required_patterns = [ "/.env*", "/.rails_master_key", "/config/master.key", "/config/credentials/*.key" ]
        missing = required_patterns.reject { |pattern| dockerignore.lines.any? { |line| line.strip == pattern } }
        return if missing.empty?

        raise CommandError, "Docker build context exclusions are missing: #{missing.join(", ")}"
      end

      def base_url
        env.fetch("ATLAS_URL") { "#{env.fetch("ATLAS_SCHEME", "https")}://#{host}" }.sub(%r{/$}, "")
      end

      def host
        URI.parse(configured_base_url).host || env.fetch("ATLAS_HOST", "atlas.home.arpa")
      end

      def configured_base_url
        env.fetch("ATLAS_URL") { "#{env.fetch("ATLAS_SCHEME", "https")}://#{env.fetch("ATLAS_HOST", "atlas.home.arpa")}" }
      end
    end

    class DeployWorkflow
      VALID_ACTIONS = %w[fresh update restart seed rollback].freeze
      DEFAULT_RAILS_MASTER_KEY_FILE = "/srv/platform/secrets/atlas/rails_master_key"

      def initialize(
        runner: CommandRunner.new,
        verifier: nil,
        readiness_waiter: nil,
        readiness_timeout: ReadinessWaiter::DEFAULT_TIMEOUT,
        readiness_poll_interval: ReadinessWaiter::DEFAULT_POLL_INTERVAL,
        readiness_clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
        readiness_sleeper: ->(duration) { sleep(duration) },
        readiness_secret_values: nil,
        env: ENV,
        repository_root: Pathname(__dir__).join("../..").expand_path
      )
        @runner = runner
        @env = env
        @verifier = verifier || Verifier.new(runner:, env:)
        @readiness_waiter = readiness_waiter || ReadinessWaiter.new(
          runner:,
          timeout: readiness_timeout,
          poll_interval: readiness_poll_interval,
          clock: readiness_clock,
          sleeper: readiness_sleeper,
          secret_values: readiness_secret_values || readiness_secret_values_from_environment
        )
        @repository_root = Pathname(repository_root)
      end

      def run(action, arguments: [])
        action = action.to_s
        raise ArgumentError, usage unless VALID_ACTIONS.include?(action)

        case action
        when "fresh"
          run_deployment
        when "update"
          marker = landing_marker
          run_deployment
          verify_marker(marker, landing_marker)
        when "restart"
          marker = persistence_marker
          compose("restart", SERVICE)
          readiness_waiter.wait
          verifier.verify
          verify_marker(marker, persistence_marker)
        when "seed"
          rails_task("db:prepare")
          rails_task("db:seed")
          verifier.verify
        when "rollback"
          rollback(arguments)
        end
      end

      private

      attr_reader :runner, :verifier, :readiness_waiter, :env, :repository_root

      def usage
        "usage: bin/deploy [fresh, update, restart, seed, rollback IMAGE_REF --confirm]"
      end

      def compose(*arguments)
        runner.run(COMPOSE + arguments)
      end

      def rails_task(task)
        compose("exec", "--no-TTY", SERVICE, "./bin/docker-entrypoint", "./bin/rails", task)
      end

      def readiness_secret_values_from_environment
        values = [ env.fetch("RAILS_MASTER_KEY", "") ]
        secret_path = env.fetch("RAILS_MASTER_KEY_FILE", DEFAULT_RAILS_MASTER_KEY_FILE)
        values << File.read(secret_path).strip if File.file?(secret_path)
        values
      rescue Errno::EACCES, Errno::EISDIR, Errno::ENOENT
        values
      end

      def run_deployment
        compose("config", "--quiet")
        compose("build", SERVICE)
        compose("up", "--detach", SERVICE)
        rails_task("db:prepare")
        rails_task("db:seed")
        readiness_waiter.wait
        verifier.verify
      end

      def landing_marker
        runner.capture(
          COMPOSE + [
            "exec", "--no-TTY", SERVICE, "./bin/docker-entrypoint", "./bin/rails", "runner",
            'require "digest"; page = ManualPage.find_by!(slug: "index"); puts [page.id, page.created_at.iso8601(6), Digest::SHA256.hexdigest(page.content)].join(" ")'
          ]
        ).strip
      end

      def persistence_marker
        runner.capture(
          COMPOSE + [
            "exec", "--no-TTY", SERVICE, "./bin/docker-entrypoint", "./bin/rails", "runner",
            'require "digest"; page = ManualPage.find_by!(slug: "index"); database = ActiveRecord::Base.connection_db_config.database; puts [page.id, page.created_at.iso8601(6), Digest::SHA256.hexdigest(page.content), Digest::SHA256.file(database).hexdigest].join(" ")'
          ]
        ).strip
      end

      def verify_marker(before, after)
        return if before == after

        raise CommandError, "primary SQLite persistence marker changed unexpectedly"
      end

      def rollback(arguments)
        image_ref = confirmed_argument(arguments, "rollback", "an image reference")
        compose("config", "--quiet")
        runner.run([ "docker", "image", "inspect", image_ref ])
        image_name = runner.capture(COMPOSE + [ "config", "--images" ]).lines.map(&:strip).find { |image| !image.empty? }
        raise CommandError, "Compose did not provide a local image name for #{SERVICE}" if image_name.to_s.empty?

        runner.run([ "docker", "tag", image_ref, image_name ])
        compose("up", "--detach", "--no-build", SERVICE)
        readiness_waiter.wait
        verifier.verify
      end

      def confirmed_argument(arguments, action, description)
        values = Array(arguments).dup
        confirmed = values.delete("--confirm")
        raise ArgumentError, "#{action} requires #{description} and --confirm" unless confirmed && values.one?

        values.first
      end
    end
  end
end
