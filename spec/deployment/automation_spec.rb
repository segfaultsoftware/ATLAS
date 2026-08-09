require "fileutils"
require "open3"
require "pathname"
require "rbconfig"
require "tempfile"
require "tmpdir"

require_relative "../../lib/atlas/deployment_automation"

class RealCheckoutRunner
  attr_reader :commands

  def initialize
    @commands = []
  end

  def capture(command, environment: {}, chdir: nil)
    @commands << [ :capture, command, environment, chdir ]
    stdout, stderr, status = Open3.capture3(environment, *command, chdir: chdir)
    raise stderr unless status.success?

    stdout
  end

  def run(command, environment: {}, chdir: nil)
    @commands << [ :run, command, environment, chdir ]
    return true unless command.first == "git"

    system(environment, *command, chdir:, exception: true)
  end
end

RSpec.describe Atlas::DeploymentAutomation::DeploymentAutomationCommandRunner do
  it "limits Git authentication to remote Git child commands" do
    runner = described_class.new(git_auth: "AUTHORIZATION: bearer test-token")

    expect(runner.send(:command_environment, %w[git push], {})).to include(
      "GIT_CONFIG_COUNT" => "1",
      "GIT_CONFIG_KEY_0" => "http.https://github.com/.extraheader",
      "GIT_CONFIG_VALUE_0" => "AUTHORIZATION: bearer test-token"
    )
    expect(runner.send(:command_environment, %w[bin/deploy update], {})).to eq({})
    expect(runner.send(:command_environment, %w[git status], {})).to eq({})
    expect(runner.send(:command_environment, [ "git", "-c", "core.hooksPath=/dev/null", "checkout", "--detach", "revision" ], {})).to eq({})
  end

  it "does not allow repository hooks to run in deployment checkouts" do
    runner = described_class.new(git_auth: "AUTHORIZATION: bearer test-token")

    expect(runner.send(:command_environment, [ "git", "-c", "core.hooksPath=/dev/null", "fetch", "origin", "revision" ], {})).to include(
      "GIT_CONFIG_VALUE_0" => "AUTHORIZATION: bearer test-token"
    )
  end

  it "bounds and redacts failed command output" do
    runner = described_class.new(secret_values: [ "raw-secret" ])

    expect do
      runner.run([
        RbConfig.ruby, "-e",
        'STDERR.write("Authorization: Bearer bearer-secret RAILS_MASTER_KEY=key-secret password=\\"super secret\\" raw-secret #{"x" * 100_000}"); exit 3'
      ])
    end.to raise_error(Atlas::Deployment::CommandError) do |error|
      expect(error.message).not_to include("bearer-secret", "key-secret", "super secret", "raw-secret")
      expect(error.message.bytesize).to be < 40_000
    end
  end

  it "redacts Rails-key-shaped values without a configured secret value" do
    possible_key = "a1b2c3d4e5f60718293a4b5c6d7e8f90"
    runner = described_class.new

    expect do
      runner.run([
        RbConfig.ruby, "-e", "STDERR.write('#{possible_key}'); exit 3"
      ])
    end.to raise_error(Atlas::Deployment::CommandError) { |error| expect(error.message).not_to include(possible_key) }
  end
end

RSpec.describe Atlas::DeploymentAutomation do
  let(:checkout_root) { Pathname.new(Dir.mktmpdir("atlas-deployment-")) }
  let(:production_root) { checkout_root.join("production") }
  let(:staging_root) { checkout_root.join("staging") }
  let(:runner) { instance_double(Atlas::DeploymentAutomation::DeploymentAutomationCommandRunner) }
  let(:automation) do
    described_class.new(
      runner:,
      production_root:,
      staging_root:,
      event: event
    )
  end
  let(:event) do
    {
      "name" => "push",
      "ref" => "refs/tags/prod",
      "before" => "0" * 40,
      "after" => "a" * 40
    }
  end

  before do
    production_root.mkpath
    staging_root.mkpath
    allow(runner).to receive(:capture).and_return("")
    allow(runner).to receive(:run)
  end

  after do
    FileUtils.remove_entry(checkout_root)
  end

  def ls_remote_line(ref, sha)
    "#{sha}\t#{ref}\n"
  end

  it "ignores unrelated push refs without touching a checkout" do
    event["ref"] = "refs/heads/feature"

    expect(automation.run).to eq(:ignored)
    expect(runner).not_to have_received(:capture)
    expect(runner).not_to have_received(:run)
  end

  it "ignores recognized deployment refs from non-push events" do
    event["name"] = "workflow_dispatch"
    event.delete("before")
    event.delete("after")

    expect(automation.run).to eq(:ignored)
    expect(runner).not_to have_received(:capture)
    expect(runner).not_to have_received(:run)
  end

  it "ignores deleted deployment refs without touching a checkout or remote ref" do
    [ Atlas::DeploymentAutomation::MAIN_REF, Atlas::DeploymentAutomation::PRODUCTION_REF ].each do |ref|
      event["ref"] = ref
      event["deleted"] = "true"

      expect(automation.run).to eq(:ignored)
    end

    expect(runner).not_to have_received(:capture)
    expect(runner).not_to have_received(:run)
  end

  it "does not deploy a stale production tag event" do
    allow(runner).to receive(:capture).with([ "git", "-c", "core.hooksPath=/dev/null", "ls-remote", "origin", "refs/tags/prod", "refs/tags/prod^{}" ]).and_return(
      ls_remote_line("refs/tags/prod", "b" * 40)
    )

    expect(automation.run).to eq(:ignored)
    expect(runner).not_to have_received(:run)
  end

  it "deploys the current production tag from a clean detached checkout" do
    allow(runner).to receive(:capture).with([ "git", "-c", "core.hooksPath=/dev/null", "ls-remote", "origin", "refs/tags/prod", "refs/tags/prod^{}" ]).and_return(
      ls_remote_line("refs/tags/prod", event.fetch("after"))
    )
    allow(runner).to receive(:capture).with([ "git", "-c", "core.hooksPath=/dev/null", "status", "--porcelain=v1", "--ignored", "--untracked-files=normal", "--", ".", ":(exclude)storage" ]).and_return("")

    expect(automation.run).to eq(:production)
    expect(runner).to have_received(:run).with(
      [ "git", "-c", "core.hooksPath=/dev/null", "fetch", "--no-tags", "origin", event.fetch("after") ], chdir: production_root.to_s, environment: {}
    ).ordered
    expect(runner).to have_received(:run).with(
      [ "git", "-c", "core.hooksPath=/dev/null", "checkout", "--detach", "--force", event.fetch("after") ], chdir: production_root.to_s, environment: {}
    ).ordered
    expect(runner).to have_received(:run).with(
      %w[bin/deploy update], chdir: production_root.to_s, environment: { "ATLAS_HOST" => "atlas.home.arpa" }
    ).ordered
    expect(runner).to have_received(:run).with(
      %w[bin/verify-deployment], chdir: production_root.to_s, environment: { "ATLAS_HOST" => "atlas.home.arpa" }
    ).ordered
  end

  it "rechecks production freshness after checkout synchronization" do
    allow(runner).to receive(:capture).with([ "git", "-c", "core.hooksPath=/dev/null", "ls-remote", "origin", "refs/tags/prod", "refs/tags/prod^{}" ]).and_return(
      ls_remote_line("refs/tags/prod", event.fetch("after")),
      ls_remote_line("refs/tags/prod", "b" * 40)
    )
    allow(runner).to receive(:capture).with([ "git", "-c", "core.hooksPath=/dev/null", "status", "--porcelain=v1", "--ignored", "--untracked-files=normal", "--", ".", ":(exclude)storage" ]).and_return("")

    expect { automation.run }.to raise_error(Atlas::Deployment::CommandError, /prod ref changed/)
    expect(runner).not_to have_received(:run).with(
      %w[bin/deploy update], chdir: production_root.to_s, environment: { "ATLAS_HOST" => "atlas.home.arpa" }
    )
  end

  it "leaves an absent staging tag unchanged" do
    event["ref"] = "refs/heads/main"
    allow(runner).to receive(:capture).with([ "git", "-c", "core.hooksPath=/dev/null", "ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}" ]).and_return("")

    expect(automation.run).to eq(:ignored)
    expect(runner).not_to have_received(:run)
  end

  it "preserves an intentionally pinned staging tag" do
    event["ref"] = "refs/heads/main"
    allow(runner).to receive(:capture).with([ "git", "-c", "core.hooksPath=/dev/null", "ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}" ]).and_return(
      ls_remote_line("refs/tags/staging", "c" * 40)
    )

    expect(automation.run).to eq(:ignored)
    expect(runner).not_to have_received(:run)
  end

  it "advances tracking staging with a compare-and-swap and deploys the new revision" do
    event["ref"] = "refs/heads/main"
    allow(runner).to receive(:capture).with([ "git", "-c", "core.hooksPath=/dev/null", "ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}" ]).and_return(
      ls_remote_line("refs/tags/staging", event.fetch("before")),
      ls_remote_line("refs/tags/staging", event.fetch("after"))
    )
    allow(runner).to receive(:capture).with([ "git", "-c", "core.hooksPath=/dev/null", "status", "--porcelain=v1", "--ignored", "--untracked-files=normal", "--", ".", ":(exclude)storage" ]).and_return("")

    expect(automation.run).to eq(:staging)
    expect(runner).to have_received(:run).with([
      "git", "-c", "core.hooksPath=/dev/null", "push", "origin", "#{event.fetch("after")}:refs/tags/staging",
      "--force-with-lease=refs/tags/staging:#{event.fetch("before")}"
    ]).ordered
    expect(runner).to have_received(:run).with(
      [ "git", "-c", "core.hooksPath=/dev/null", "checkout", "--detach", "--force", event.fetch("after") ], chdir: staging_root.to_s, environment: {}
    ).ordered
    expect(runner).to have_received(:run).with(
      %w[bin/deploy update], chdir: staging_root.to_s, environment: { "ATLAS_HOST" => "atlas-staging.home.arpa" }
    ).ordered
  end

  it "accepts an annotated production tag when its peeled commit matches" do
    tag_object = "b" * 40
    allow(runner).to receive(:capture).with([ "git", "-c", "core.hooksPath=/dev/null", "ls-remote", "origin", "refs/tags/prod", "refs/tags/prod^{}" ]).and_return(
      ls_remote_line("refs/tags/prod", tag_object) + ls_remote_line("refs/tags/prod^{}", event.fetch("after"))
    )
    allow(runner).to receive(:capture).with([ "git", "-c", "core.hooksPath=/dev/null", "status", "--porcelain=v1", "--ignored", "--untracked-files=normal", "--", ".", ":(exclude)storage" ]).and_return("")

    expect(automation.run).to eq(:production)
    expect(runner).to have_received(:run).with(
      %w[bin/deploy update], chdir: production_root.to_s, environment: { "ATLAS_HOST" => "atlas.home.arpa" }
    )
  end

  it "treats an already advanced staging tag as a safe retry" do
    event["ref"] = "refs/heads/main"
    allow(runner).to receive(:capture).with([ "git", "-c", "core.hooksPath=/dev/null", "ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}" ]).and_return(
      ls_remote_line("refs/tags/staging", event.fetch("after"))
    )
    allow(runner).to receive(:capture).with([ "git", "-c", "core.hooksPath=/dev/null", "status", "--porcelain=v1", "--ignored", "--untracked-files=normal", "--", ".", ":(exclude)storage" ]).and_return("")

    expect(automation.run).to eq(:staging)
    expect(runner).not_to have_received(:run).with(array_including("git", "push"))
    expect(runner).to have_received(:run).with(
      %w[bin/deploy update], chdir: staging_root.to_s, environment: { "ATLAS_HOST" => "atlas-staging.home.arpa" }
    )
  end

  it "uses an annotated staging tag object for the compare-and-swap lease" do
    event["ref"] = "refs/heads/main"
    tag_object = "c" * 40
    allow(runner).to receive(:capture).with([ "git", "-c", "core.hooksPath=/dev/null", "ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}" ]).and_return(
      ls_remote_line("refs/tags/staging", tag_object) + ls_remote_line("refs/tags/staging^{}", event.fetch("before")),
      ls_remote_line("refs/tags/staging", event.fetch("after"))
    )
    allow(runner).to receive(:capture).with([ "git", "-c", "core.hooksPath=/dev/null", "status", "--porcelain=v1", "--ignored", "--untracked-files=normal", "--", ".", ":(exclude)storage" ]).and_return("")

    expect(automation.run).to eq(:staging)
    expect(runner).to have_received(:run).with([
      "git", "-c", "core.hooksPath=/dev/null", "push", "origin", "#{event.fetch("after")}:refs/tags/staging",
      "--force-with-lease=refs/tags/staging:#{tag_object}"
    ])
  end

  it "fails visibly and does not deploy when staging compare-and-swap loses a race" do
    event["ref"] = "refs/heads/main"
    allow(runner).to receive(:capture).with([ "git", "-c", "core.hooksPath=/dev/null", "ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}" ]).and_return(
      ls_remote_line("refs/tags/staging", event.fetch("before"))
    )
    allow(runner).to receive(:run).with([
      "git", "-c", "core.hooksPath=/dev/null", "push", "origin", "#{event.fetch("after")}:refs/tags/staging",
      "--force-with-lease=refs/tags/staging:#{event.fetch("before")}"
    ]).and_raise(Atlas::Deployment::CommandError, "lease rejected; token=secret")

    expect { automation.run }.to raise_error(Atlas::Deployment::CommandError) do |error|
      expect(error.message).to include("lease rejected")
      expect(error.message).not_to include("secret")
    end
    expect(runner).not_to have_received(:run).with(%w[bin/deploy update])
    expect(automation.send(:remote_revision, Atlas::DeploymentAutomation::STAGING_REF)).to eq(event.fetch("before"))
  end

  it "rejects a staging update when the post-push ref verification is not the requested revision" do
    event["ref"] = "refs/heads/main"
    allow(runner).to receive(:capture).with([ "git", "-c", "core.hooksPath=/dev/null", "ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}" ]).and_return(
      ls_remote_line("refs/tags/staging", event.fetch("before")),
      ls_remote_line("refs/tags/staging", "c" * 40)
    )

    expect { automation.run }.to raise_error(Atlas::Deployment::CommandError, /did not advance/)
    expect(runner).not_to have_received(:run).with(%w[bin/deploy update])
  end

  it "rejects a checkout with tracked or visible untracked changes" do
    allow(runner).to receive(:capture).with([ "git", "-c", "core.hooksPath=/dev/null", "ls-remote", "origin", "refs/tags/prod", "refs/tags/prod^{}" ]).and_return(
      ls_remote_line("refs/tags/prod", event.fetch("after"))
    )
    allow(runner).to receive(:capture).with(
      [ "git", "-c", "core.hooksPath=/dev/null", "status", "--porcelain=v1", "--ignored", "--untracked-files=normal", "--", ".", ":(exclude)storage" ], chdir: production_root.to_s, environment: {}
    ).and_return(" M compose.yaml\n")

    expect { automation.run }.to raise_error(Atlas::Deployment::CommandError, /not clean/)
    expect(runner).not_to have_received(:run)
  end

  it "rejects ignored checkout state outside the approved environment and storage paths" do
    allow(runner).to receive(:capture).with([ "git", "-c", "core.hooksPath=/dev/null", "ls-remote", "origin", "refs/tags/prod", "refs/tags/prod^{}" ]).and_return(
      ls_remote_line("refs/tags/prod", event.fetch("after"))
    )
    allow(runner).to receive(:capture).with(
      [ "git", "-c", "core.hooksPath=/dev/null", "status", "--porcelain=v1", "--ignored", "--untracked-files=normal", "--", ".", ":(exclude)storage" ], chdir: production_root.to_s, environment: {}
    ).and_return("!! local-compose.override\n")

    expect { automation.run }.to raise_error(Atlas::Deployment::CommandError, /unapproved ignored files/)
  end

  it "loads the file-backed Rails master key into the command redaction set" do
    secret_file = Tempfile.new("atlas-master-key")
    secret_file.write("file-backed-secret\n")
    secret_file.flush
    production_root.join(".env").write("RAILS_MASTER_KEY_FILE=#{secret_file.path}\n")
    automation = described_class.new(production_root: production_root, event: {})

    expect(automation.send(:deployment_secret_values)).to include("file-backed-secret")
    expect do
      automation.instance_variable_get(:@runner).run([
        RbConfig.ruby, "-e", 'STDERR.write("RAILS_MASTER_KEY=file-backed-secret"); exit 3'
      ])
    end.to raise_error(Atlas::Deployment::CommandError) { |error| expect(error.message).not_to include("file-backed-secret") }
  ensure
    secret_file&.close!
  end

  it "preserves ignored environment and storage files through checkout synchronization" do
    repository = checkout_root.join("integration")
    repository.mkpath
    system("git", "init", "--quiet", chdir: repository, exception: true)
    system("git", "config", "user.email", "test@example.com", chdir: repository, exception: true)
    system("git", "config", "user.name", "ATLAS Test", chdir: repository, exception: true)
    system("git", "remote", "add", "origin", repository.to_s, chdir: repository, exception: true)
    repository.join(".gitignore").write(".env\nstorage/\n")
    repository.join("tracked.txt").write("first\n")
    system("git", "add", ".", chdir: repository, exception: true)
    system("git", "commit", "--quiet", "-m", "first", chdir: repository, exception: true)
    first_revision = Open3.capture3("git", "rev-parse", "HEAD", chdir: repository.to_s).first.strip
    repository.join("tracked.txt").write("second\n")
    system("git", "add", "tracked.txt", chdir: repository, exception: true)
    system("git", "commit", "--quiet", "-m", "second", chdir: repository, exception: true)
    repository.join(".env").write("RAILS_MASTER_KEY_FILE=/srv/secret\n")
    repository.join("storage").mkpath
    repository.join("storage/uploads.txt").write("persistent\n")
    real_runner = RealCheckoutRunner.new
    automation = described_class.new(runner: real_runner, production_root: repository, event: event)

    automation.send(:deploy_revision, root: repository.to_s, revision: first_revision, host: "atlas.home.arpa")

    expect(repository.join("tracked.txt").read).to eq("first\n")
    expect(repository.join(".env").read).to include("RAILS_MASTER_KEY_FILE")
    expect(repository.join("storage/uploads.txt").read).to eq("persistent\n")
  end

  it "stops before verification when the deployment command fails" do
    allow(runner).to receive(:capture).with([ "git", "-c", "core.hooksPath=/dev/null", "ls-remote", "origin", "refs/tags/prod", "refs/tags/prod^{}" ]).and_return(
      ls_remote_line("refs/tags/prod^{}", event.fetch("after"))
    )
    allow(runner).to receive(:capture).with([ "git", "-c", "core.hooksPath=/dev/null", "status", "--porcelain=v1", "--ignored", "--untracked-files=normal", "--", ".", ":(exclude)storage" ]).and_return("")
    allow(runner).to receive(:run).with(
      %w[bin/deploy update], chdir: production_root.to_s, environment: { "ATLAS_HOST" => "atlas.home.arpa" }
    ).and_raise(Atlas::Deployment::CommandError, "deploy failed; token=secret")

    expect { automation.run }.to raise_error(Atlas::Deployment::CommandError) do |error|
      expect(error.message).to include("deploy failed")
      expect(error.message).not_to include("secret")
    end
    expect(runner).not_to have_received(:run).with(
      %w[bin/verify-deployment], chdir: production_root.to_s, environment: { "ATLAS_HOST" => "atlas.home.arpa" }
    )
  end
end
