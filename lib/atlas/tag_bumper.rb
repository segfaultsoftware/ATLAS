require "pathname"

require_relative "deployment_automation"

module Atlas
  class TagBumper
    CommandError = Deployment::CommandError

    SHA_PATTERN = /\A[0-9a-f]{40}\z/i
    MAX_DIAGNOSTIC_BYTES = 4_096

    def initialize(
      tag_ref:,
      target_label:,
      runner: nil,
      repository_root: Pathname(__dir__).join("../..").expand_path,
      remote: "origin",
      secret_values: [],
      git_auth: nil,
      output: $stdout
    )
      @tag_ref = tag_ref.to_s
      @target_label = target_label.to_s
      @secret_values = (Array(secret_values) + [ git_auth ]).filter_map do |value|
        value = value.to_s
        value unless value.empty?
      end.freeze
      @runner = runner || DeploymentAutomation::DeploymentAutomationCommandRunner.new(secret_values: @secret_values, git_auth:)
      @repository_root = Pathname(repository_root)
      @remote = remote.to_s
      @output = output
    end

    def run
      expected_revision = committed_head
      expected_remote_revision = remote_ref_revisions.fetch(:direct).to_s

      execute(
        git_command(
          "push", remote, "#{expected_revision}:#{tag_ref}",
          "--force-with-lease=#{tag_ref}:#{expected_remote_revision}"
        )
      )

      observed_revision = remote_revision
      unless observed_revision == expected_revision
        raise CommandError,
          "#{target_label} tag verification failed: expected #{expected_revision}, observed #{observed_revision || "missing"}; inspect #{tag_ref} and retry"
      end

      output.puts "Updated #{tag_ref} to #{expected_revision}"
      :updated
    rescue CommandError => error
      raise error if error.message.start_with?("#{target_label} tag verification failed:")

      raise CommandError, "could not update #{tag_ref} to #{expected_revision || "committed HEAD"}: #{bounded_diagnostic(error.message)}; inspect the remote ref and retry"
    end

    private

    attr_reader :runner, :repository_root, :remote, :secret_values, :output, :tag_ref, :target_label

    def committed_head
      revision = capture(git_command("rev-parse", "--verify", "HEAD^{commit}")).strip
      return revision if SHA_PATTERN.match?(revision)

      raise CommandError, "could not resolve committed HEAD"
    end

    def remote_revision
      revisions = remote_ref_revisions
      revisions[:peeled] || revisions[:direct]
    end

    def remote_ref_revisions
      command_output = capture(git_command("ls-remote", remote, tag_ref, "#{tag_ref}^{}"))
      revisions = command_output.to_s.lines.filter_map do |line|
        revision, returned_ref = line.split(/\s+/, 2)
        next unless revision && returned_ref

        [ returned_ref.strip, revision ]
      end.to_h

      { direct: revisions[tag_ref], peeled: revisions["#{tag_ref}^{}"] }
    end

    def git_command(subcommand, *arguments)
      [ "git", "-c", "core.hooksPath=/dev/null", subcommand, *arguments ]
    end

    def capture(command)
      runner.capture(command, chdir: repository_root.to_s, environment: {})
    end

    def execute(command)
      runner.run(command, chdir: repository_root.to_s, environment: {})
    end

    def bounded_diagnostic(value)
      sanitized = value.to_s.dup
      secret_values.each { |secret| sanitized.gsub!(secret, "[REDACTED]") }
      sanitized.gsub!(/(Bearer\s+)([^\s]+)/i, "\\1[REDACTED]")
      sanitized.lines.first(40).join.byteslice(0, MAX_DIAGNOSTIC_BYTES).to_s.scrub
    end
  end
end
