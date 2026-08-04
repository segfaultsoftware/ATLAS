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

      def initialize(runner: CommandRunner.new, verifier: nil, env: ENV, repository_root: Pathname(__dir__).join("../..").expand_path)
        @runner = runner
        @env = env
        @verifier = verifier || Verifier.new(runner:, env:)
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

      attr_reader :runner, :verifier, :env, :repository_root

      def usage
        "usage: bin/deploy [fresh, update, restart, seed, rollback IMAGE_REF --confirm]"
      end

      def compose(*arguments)
        runner.run(COMPOSE + arguments)
      end

      def rails_task(task)
        compose("exec", "--no-TTY", SERVICE, "./bin/docker-entrypoint", "./bin/rails", task)
      end

      def run_deployment
        compose("config", "--quiet")
        compose("build", SERVICE)
        compose("up", "--detach", SERVICE)
        rails_task("db:prepare")
        rails_task("db:seed")
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
