require "pathname"
require "open3"
require "rbconfig"
require "tmpdir"

require_relative "../../lib/atlas/deployment_automation"
require_relative "../../lib/atlas/tag_bumper"

RSpec.describe Atlas::TagBumper do
  let(:repository_root) { Pathname.new("/srv/apps/ATLAS") }
  let(:runner) { instance_double(Atlas::DeploymentAutomation::DeploymentAutomationCommandRunner) }
  let(:head_revision) { "a" * 40 }
  let(:previous_revision) { "b" * 40 }
  let(:bumper) do
    described_class.new(
      tag_ref: Atlas::DeploymentAutomation::PRODUCTION_REF,
      target_label: "production",
      runner:,
      repository_root:
    )
  end

  def git_command(*arguments)
    [ "git", "-c", "core.hooksPath=/dev/null", *arguments ]
  end

  def ls_remote_line(ref, revision)
    "#{revision}\t#{ref}\n"
  end

  before do
    allow(runner).to receive(:capture).with(
      git_command("rev-parse", "--verify", "HEAD^{commit}"),
      chdir: repository_root.to_s,
      environment: {}
    ).and_return("#{head_revision}\n")
    allow(runner).to receive(:capture).with(
      git_command("ls-remote", "origin", "refs/tags/prod", "refs/tags/prod^{}"),
      chdir: repository_root.to_s,
      environment: {}
    ).and_return(
      "#{previous_revision}\trefs/tags/prod\n",
      "#{head_revision}\trefs/tags/prod\n"
    )
    allow(runner).to receive(:run)
  end

  it "forwards Git authentication to the default command runner" do
    git_auth = "AUTHORIZATION: bearer app-token-value"
    expect(Atlas::DeploymentAutomation::DeploymentAutomationCommandRunner).to receive(:new).with(
      secret_values: [ "app-token-value", git_auth ],
      git_auth:
    ).and_return(runner)

    described_class.new(
      tag_ref: Atlas::DeploymentAutomation::PRODUCTION_REF,
      target_label: "production",
      repository_root:,
      secret_values: [ "app-token-value" ],
      git_auth:
    )
  end

  it "advances the production tag with the shared direct-ref lease behavior" do
    expect(bumper.run).to eq(:updated)
    expect(runner).to have_received(:run).with(
      git_command(
        "push", "origin", "#{head_revision}:refs/tags/prod",
        "--force-with-lease=refs/tags/prod:#{previous_revision}"
      ),
      chdir: repository_root.to_s,
      environment: {}
    )
    expect(runner).not_to have_received(:capture).with(
      array_including("status"),
      any_args
    )
  end

  it "uses an empty explicit lease when the production tag does not exist yet" do
    allow(runner).to receive(:capture).with(
      git_command("ls-remote", "origin", "refs/tags/prod", "refs/tags/prod^{}"),
      chdir: repository_root.to_s,
      environment: {}
    ).and_return("", ls_remote_line("refs/tags/prod", head_revision))

    expect(bumper.run).to eq(:updated)
    expect(runner).to have_received(:run).with(
      git_command(
        "push", "origin", "#{head_revision}:refs/tags/prod",
        "--force-with-lease=refs/tags/prod:"
      ),
      chdir: repository_root.to_s,
      environment: {}
    )
  end

  it "accepts an annotated production tag when its peeled target is committed HEAD" do
    tag_object = "c" * 40
    allow(runner).to receive(:capture).with(
      git_command("ls-remote", "origin", "refs/tags/prod", "refs/tags/prod^{}"),
      chdir: repository_root.to_s,
      environment: {}
    ).and_return(
      ls_remote_line("refs/tags/prod", previous_revision),
      ls_remote_line("refs/tags/prod", tag_object) + ls_remote_line("refs/tags/prod^{}", head_revision)
    )

    expect(bumper.run).to eq(:updated)
    expect(runner).to have_received(:run).with(
      git_command(
        "push", "origin", "#{head_revision}:refs/tags/prod",
        "--force-with-lease=refs/tags/prod:#{previous_revision}"
      ),
      chdir: repository_root.to_s,
      environment: {}
    )
  end

  it "redacts authentication and bounds diagnostics when the production push is rejected" do
    allow(runner).to receive(:run).with(
      git_command(
        "push", "origin", "#{head_revision}:refs/tags/prod",
        "--force-with-lease=refs/tags/prod:#{previous_revision}"
      ),
      chdir: repository_root.to_s,
      environment: {}
    ).and_raise(
      Atlas::Deployment::CommandError,
      "remote rejected: Authorization: Bearer app-token-value #{'x' * 10_000}"
    )

    expect { bumper.run }.to raise_error(Atlas::Deployment::CommandError) do |error|
      expect(error.message).to include("refs/tags/prod", head_revision, "retry")
      expect(error.message).not_to include("app-token-value")
      expect(error.message.bytesize).to be < 5_000
    end
  end

  it "reports expected and observed revisions when production verification mismatches" do
    observed_revision = "d" * 40
    allow(runner).to receive(:capture).with(
      git_command("ls-remote", "origin", "refs/tags/prod", "refs/tags/prod^{}"),
      chdir: repository_root.to_s,
      environment: {}
    ).and_return(
      ls_remote_line("refs/tags/prod", previous_revision),
      ls_remote_line("refs/tags/prod", observed_revision)
    )

    expect { bumper.run }.to raise_error(Atlas::Deployment::CommandError) do |error|
      expect(error.message).to include("expected #{head_revision}", "observed #{observed_revision}", "retry")
    end
  end
end

RSpec.describe "bin/bump_prod_tag" do
  let(:entrypoint) { File.expand_path("../../bin/bump_prod_tag", __dir__) }

  it "rejects arguments before invoking deployment dependencies" do
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, entrypoint, "unexpected")

    expect(status.success?).to be(false)
    expect(stderr).to include("usage: bin/bump_prod_tag")
  end

  it "clears authentication variables and delegates to the production tag" do
    head_revision = "a" * 40
    previous_revision = "b" * 40

    Dir.mktmpdir("bump-prod-tag") do |directory|
      fake_git = File.join(directory, "git")
      git_log = File.join(directory, "git.log")
      git_calls = File.join(directory, "git.calls")
      observed_environment = File.join(directory, "environment.log")

      File.write(fake_git, <<~RUBY)
        #!/usr/bin/env ruby

        File.open(ENV.fetch("ATLAS_TEST_GIT_LOG"), "a") do |file|
          file.puts(ARGV.join(" "))
        end
        File.open(ENV.fetch("ATLAS_TEST_GIT_ENVIRONMENT"), "a") do |file|
          file.puts(
            %w[GIT_CONFIG_VALUE_0 GIT_CONFIG_COUNT GIT_CONFIG_KEY_0].map do |key|
              "\#{key}=\#{ENV[key].inspect}"
            end.join(" ")
          )
        end

        if ARGV.include?("rev-parse")
          puts "#{head_revision}"
        elsif ARGV.include?("ls-remote")
          call_number = File.exist?(ENV.fetch("ATLAS_TEST_GIT_CALLS")) ? File.read(ENV.fetch("ATLAS_TEST_GIT_CALLS")).to_i : 0
          File.write(ENV.fetch("ATLAS_TEST_GIT_CALLS"), (call_number + 1).to_s)
          revision = call_number.zero? ? "#{previous_revision}" : "#{head_revision}"
          puts "\#{revision}\\trefs/tags/prod"
        elsif ARGV.include?("push")
          exit 0
        else
          warn "unexpected fake git command"
          exit 1
        end
      RUBY
      File.chmod(0o755, fake_git)

      environment = {
        "PATH" => "#{directory}:#{ENV.fetch("PATH")}",
        "ATLAS_TEST_GIT_LOG" => git_log,
        "ATLAS_TEST_GIT_CALLS" => git_calls,
        "ATLAS_TEST_GIT_ENVIRONMENT" => observed_environment,
        "GIT_CONFIG_VALUE_0" => "Authorization: bearer test-token",
        "GIT_CONFIG_COUNT" => "1",
        "GIT_CONFIG_KEY_0" => "http.https://github.com/.extraheader"
      }

      stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, entrypoint)

      expect(status.success?).to be(true), stderr
      expect(stdout).to include("Updated refs/tags/prod to #{head_revision}")
      expect(File.read(git_log)).to include(
        "push origin #{head_revision}:refs/tags/prod --force-with-lease=refs/tags/prod:#{previous_revision}"
      )
      expect(File.read(observed_environment)).to include(
        "GIT_CONFIG_VALUE_0=nil",
        "GIT_CONFIG_COUNT=nil",
        "GIT_CONFIG_KEY_0=nil",
        "GIT_CONFIG_VALUE_0=\"Authorization: bearer test-token\""
      )
    end
  end

  it "does not include staging configuration" do
    entrypoint_source = File.read(entrypoint)

    expect(entrypoint_source).not_to include("StagingTagBumper", "refs/tags/staging")
  end
end
