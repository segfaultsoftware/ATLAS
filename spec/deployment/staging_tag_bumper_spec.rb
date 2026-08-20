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

  it "configures the reusable tag bumper for staging" do
    expect(described_class.superclass).to eq(Atlas::TagBumper)
    expect(described_class::STAGING_REF).to eq(Atlas::DeploymentAutomation::STAGING_REF)
  end

  it "moves staging to committed HEAD through the compatibility wrapper" do
    expect(bumper.run).to eq(:updated)
    expect(runner).to have_received(:run).with(
      git_command(
        "push", "origin", "#{head_revision}:refs/tags/staging",
        "--force-with-lease=refs/tags/staging:#{previous_revision}"
      ),
      chdir: repository_root.to_s,
      environment: {}
    )
  end

  it "does not allow callers to override the staging target" do
    configured_bumper = described_class.new(
      tag_ref: Atlas::DeploymentAutomation::PRODUCTION_REF,
      target_label: "production",
      runner:,
      repository_root:
    )

    expect(configured_bumper.run).to eq(:updated)
    expect(runner).to have_received(:run).with(
      git_command(
        "push", "origin", "#{head_revision}:refs/tags/staging",
        "--force-with-lease=refs/tags/staging:#{previous_revision}"
      ),
      chdir: repository_root.to_s,
      environment: {}
    )
  end
end

RSpec.describe "bin/bump_staging_tag" do
  let(:entrypoint) { File.read(File.expand_path("../../bin/bump_staging_tag", __dir__)) }

  it "rejects arguments and delegates to the staging tag bumper" do
    expect(entrypoint).to include('abort "usage: bin/bump_staging_tag" unless ARGV.empty?')
    expect(entrypoint).to include("Atlas::StagingTagBumper.new(git_auth:).run")
  end
end
