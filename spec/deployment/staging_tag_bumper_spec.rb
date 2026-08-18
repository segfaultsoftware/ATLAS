require "pathname"

require_relative "../../lib/atlas/deployment_automation"
require_relative "../../lib/atlas/staging_tag_bumper"

RSpec.describe Atlas::StagingTagBumper do
  let(:repository_root) { Pathname.new("/srv/apps/ATLAS") }
  let(:runner) { instance_double(Atlas::DeploymentAutomation::DeploymentAutomationCommandRunner) }
  let(:head_revision) { "a" * 40 }
  let(:previous_revision) { "b" * 40 }
  let(:bumper) do
    described_class.new(
      runner:,
      repository_root:,
      secret_values: [ "app-token-value" ]
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
      git_command("ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}"),
      chdir: repository_root.to_s,
      environment: {}
    ).and_return(
      ls_remote_line("refs/tags/staging", previous_revision),
      ls_remote_line("refs/tags/staging", head_revision)
    )
    allow(runner).to receive(:run)
  end

  it "accepts no arguments and moves staging to committed HEAD without inspecting dirty worktree state" do
    expect(bumper.run).to eq(:updated)

    expect(runner).to have_received(:capture).with(
      git_command("rev-parse", "--verify", "HEAD^{commit}"),
      chdir: repository_root.to_s,
      environment: {}
    ).ordered
    expect(runner).to have_received(:run).with(
      git_command(
        "push", "origin", "HEAD:refs/tags/staging",
        "--force-with-lease=refs/tags/staging:#{previous_revision}"
      ),
      chdir: repository_root.to_s,
      environment: {}
    ).ordered
    expect(runner).not_to have_received(:capture).with(
      array_including("status"),
      any_args
    )
  end

  it "uses an explicit lease and verifies a direct staging ref after the push" do
    allow(runner).to receive(:capture).with(
      git_command("ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}"),
      chdir: repository_root.to_s,
      environment: {}
    ).and_return(
      ls_remote_line("refs/tags/staging", previous_revision),
      ls_remote_line("refs/tags/staging", head_revision)
    )

    expect(bumper.run).to eq(:updated)

    expect(runner).to have_received(:run).with(
      git_command(
        "push", "origin", "HEAD:refs/tags/staging",
        "--force-with-lease=refs/tags/staging:#{previous_revision}"
      ),
      chdir: repository_root.to_s,
      environment: {}
    )
    expect(runner).to have_received(:capture).with(
      git_command("ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}"),
      chdir: repository_root.to_s,
      environment: {}
    ).twice
  end

  it "uses an empty explicit lease when staging does not exist yet" do
    allow(runner).to receive(:capture).with(
      git_command("ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}"),
      chdir: repository_root.to_s,
      environment: {}
    ).and_return("", ls_remote_line("refs/tags/staging", head_revision))

    expect(bumper.run).to eq(:updated)

    expect(runner).to have_received(:run).with(
      git_command(
        "push", "origin", "HEAD:refs/tags/staging",
        "--force-with-lease=refs/tags/staging:"
      ),
      chdir: repository_root.to_s,
      environment: {}
    )
  end

  it "accepts an annotated staging tag when its peeled target is committed HEAD" do
    tag_object = "c" * 40
    allow(runner).to receive(:capture).with(
      git_command("ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}"),
      chdir: repository_root.to_s,
      environment: {}
    ).and_return(
      ls_remote_line("refs/tags/staging", previous_revision),
      ls_remote_line("refs/tags/staging", tag_object) + ls_remote_line("refs/tags/staging^{}", head_revision)
    )

    expect(bumper.run).to eq(:updated)
  end

  it "reports bounded, actionable diagnostics when the protected push is rejected" do
    allow(runner).to receive(:run).with(
      git_command(
        "push", "origin", "HEAD:refs/tags/staging",
        "--force-with-lease=refs/tags/staging:#{previous_revision}"
      ),
      chdir: repository_root.to_s,
      environment: {}
    ).and_raise(
      Atlas::Deployment::CommandError,
      "remote rejected: Authorization: Bearer app-token-value #{'x' * 10_000}"
    )

    expect { bumper.run }.to raise_error(Atlas::Deployment::CommandError) do |error|
      expect(error.message).to include("refs/tags/staging", head_revision, "retry")
      expect(error.message).not_to include("app-token-value")
      expect(error.message.bytesize).to be < 5_000
    end
  end

  it "reports expected and observed revisions with retry guidance when remote verification mismatches" do
    observed_revision = "d" * 40
    allow(runner).to receive(:capture).with(
      git_command("ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}"),
      chdir: repository_root.to_s,
      environment: {}
    ).and_return(
      ls_remote_line("refs/tags/staging", previous_revision),
      ls_remote_line("refs/tags/staging", observed_revision)
    )

    expect { bumper.run }.to raise_error(Atlas::Deployment::CommandError) do |error|
      expect(error.message).to include("expected #{head_revision}", "observed #{observed_revision}", "retry")
    end
  end
end

RSpec.describe "bin/bump_staging_tag" do
  let(:entrypoint) { File.read(File.expand_path("../../bin/bump_staging_tag", __dir__)) }

  it "rejects arguments and delegates to the staging tag bumper" do
    expect(entrypoint).to include('abort "usage: bin/bump_staging_tag" unless ARGV.empty?')
    expect(entrypoint).to include("Atlas::StagingTagBumper.new(git_auth:).run")
  end
end
