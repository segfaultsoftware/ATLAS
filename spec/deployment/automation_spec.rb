require "pathname"
require "tmpdir"
require "fileutils"

require_relative "../../lib/atlas/deployment_automation"

RSpec.describe Atlas::DeploymentAutomation do
  let(:revision_before) { "1" * 40 }
  let(:revision_after) { "2" * 40 }
  let(:checkout_root) { Pathname(Dir.mktmpdir("atlas-deployment-automation")) }
  let(:production_path) { checkout_root.join("production") }
  let(:staging_path) { checkout_root.join("staging") }
  let(:runner) { instance_double(Atlas::DeploymentAutomation::CommandRunner) }

  before do
    production_path.join(".git").mkpath
    staging_path.join(".git").mkpath
    @staging_revision = revision_before

    allow(runner).to receive(:run) do |command, chdir:|
      @staging_revision = revision_after if command.first(2) == [ "git", "push" ]
    end
    allow(runner).to receive(:capture) do |command, chdir:|
      case command
      when [ "git", "ls-remote", "origin", "refs/tags/prod", "refs/tags/prod^{}" ]
        "#{revision_after}\trefs/tags/prod\n"
      when [ "git", "ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}" ]
        "#{@staging_revision}\trefs/tags/staging\n"
      when [ "git", "ls-remote", "origin", "refs/heads/main" ]
        "#{revision_after}\trefs/heads/main\n"
      when [ "git", "status", "--porcelain=v1", "--untracked-files=all" ]
        ""
      when [ "git", "rev-parse", "HEAD" ]
        revision_after
      else
        raise "unexpected capture: #{command.inspect} in #{chdir}"
      end
    end
  end

  after do
    FileUtils.remove_entry(checkout_root) if checkout_root.exist?
  end

  it "ignores unrelated push refs without touching a checkout" do
    event = described_class::Event.new(
      name: "push",
      ref: "refs/heads/feature",
      before: revision_before,
      after: revision_after
    )

    result = described_class.new(event:, runner:, production_path:, staging_path:).run

    expect(result).to include(status: :noop, reason: :unrelated_ref)
    expect(runner).not_to have_received(:capture)
    expect(runner).not_to have_received(:run)
  end

  it "deploys the current production tag revision after synchronizing the checkout" do
    event = described_class::Event.new(
      name: "push",
      ref: "refs/tags/prod",
      before: revision_before,
      after: revision_after
    )

    result = described_class.new(event:, runner:, production_path:, staging_path:).run

    expect(result).to include(status: :deployed, environment: :production, revision: revision_after)
    expect(runner).to have_received(:run).with([ "bin/deploy", "update" ], chdir: production_path.to_s).ordered
    expect(runner).to have_received(:run).with([ "bin/verify-deployment" ], chdir: production_path.to_s).ordered
  end

  it "advances tracking staging with compare-and-swap before deploying" do
    event = described_class::Event.new(
      name: "push",
      ref: "refs/heads/main",
      before: revision_before,
      after: revision_after
    )

    result = described_class.new(event:, runner:, production_path:, staging_path:).run

    expect(result).to include(status: :deployed, environment: :staging, revision: revision_after)
    expect(runner).to have_received(:run).with(
      [ "git", "push", "--force-with-lease=refs/tags/staging:#{revision_before}", "origin", "#{revision_after}:refs/tags/staging" ],
      chdir: staging_path.to_s
    ).ordered
    expect(runner).to have_received(:run).with([ "bin/deploy", "update" ], chdir: staging_path.to_s).ordered
  end

  it "uses the tag object revision for annotated staging-tag leases" do
    tag_object_revision = "9" * 40
    allow(runner).to receive(:capture).with(
      [ "git", "ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}" ], chdir: staging_path.to_s
    ).and_return(
      "#{tag_object_revision}\trefs/tags/staging\n#{revision_before}\trefs/tags/staging^{}\n",
      "#{tag_object_revision}\trefs/tags/staging\n#{revision_after}\trefs/tags/staging^{}\n"
    )

    event = described_class::Event.new(
      name: "push",
      ref: "refs/heads/main",
      before: revision_before,
      after: revision_after
    )

    described_class.new(event:, runner:, production_path:, staging_path:).run

    expect(runner).to have_received(:run).with(
      [ "git", "push", "--force-with-lease=refs/tags/staging:#{tag_object_revision}", "origin", "#{revision_after}:refs/tags/staging" ],
      chdir: staging_path.to_s
    ).ordered
  end

  it "leaves an intentionally pinned staging tag unchanged" do
    pinned_revision = "3" * 40
    allow(runner).to receive(:capture).with(
      [ "git", "ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}" ], chdir: staging_path.to_s
    ).and_return("#{pinned_revision}\trefs/tags/staging\n")

    event = described_class::Event.new(
      name: "push",
      ref: "refs/heads/main",
      before: revision_before,
      after: revision_after
    )

    result = described_class.new(event:, runner:, production_path:, staging_path:).run

    expect(result).to include(status: :noop, reason: :staging_pinned)
    expect(runner).not_to have_received(:run)
  end

  it "leaves an absent staging tag unchanged" do
    allow(runner).to receive(:capture).with(
      [ "git", "ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}" ], chdir: staging_path.to_s
    ).and_return("")
    event = described_class::Event.new(
      name: "push",
      ref: "refs/heads/main",
      before: revision_before,
      after: revision_after
    )

    result = described_class.new(event:, runner:, production_path:, staging_path:).run

    expect(result).to include(status: :noop, reason: :staging_tag_absent)
    expect(runner).not_to have_received(:run)
  end

  it "does not move staging for a delayed main event" do
    current_main = "4" * 40
    allow(runner).to receive(:capture).with(
      [ "git", "ls-remote", "origin", "refs/heads/main" ], chdir: staging_path.to_s
    ).and_return("#{current_main}\trefs/heads/main\n")
    event = described_class::Event.new(
      name: "push",
      ref: "refs/heads/main",
      before: revision_before,
      after: revision_after
    )

    result = described_class.new(event:, runner:, production_path:, staging_path:).run

    expect(result).to include(status: :noop, reason: :stale_main_event)
    expect(runner).not_to have_received(:run)
  end

  it "retries a deployment when staging already points at the event revision" do
    allow(runner).to receive(:capture).with(
      [ "git", "ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}" ], chdir: staging_path.to_s
    ).and_return("#{revision_after}\trefs/tags/staging\n")
    event = described_class::Event.new(
      name: "push",
      ref: "refs/heads/main",
      before: revision_before,
      after: revision_after
    )

    result = described_class.new(event:, runner:, production_path:, staging_path:).run

    expect(result).to include(status: :deployed, environment: :staging, revision: revision_after)
    expect(runner).not_to have_received(:run).with(
      [ "git", "push", "--force-with-lease=refs/tags/staging:#{revision_before}", "origin", "#{revision_after}:refs/tags/staging" ],
      chdir: staging_path.to_s
    )
  end

  it "fails without deploying when the staging compare-and-swap is rejected" do
    allow(runner).to receive(:run).with(
      [ "git", "push", "--force-with-lease=refs/tags/staging:#{revision_before}", "origin", "#{revision_after}:refs/tags/staging" ],
      chdir: staging_path.to_s
    ).and_raise(described_class::CommandError, "compare-and-swap rejected")
    event = described_class::Event.new(
      name: "push",
      ref: "refs/heads/main",
      before: revision_before,
      after: revision_after
    )

    expect { described_class.new(event:, runner:, production_path:, staging_path:).run }
      .to raise_error(described_class::CommandError, /compare-and-swap rejected/)
    expect(runner).not_to have_received(:run).with([ "bin/deploy", "update" ], chdir: staging_path.to_s)
  end

  it "rejects a production event when the remote tag moved elsewhere" do
    other_revision = "4" * 40
    allow(runner).to receive(:capture).with(
      [ "git", "ls-remote", "origin", "refs/tags/prod", "refs/tags/prod^{}" ], chdir: production_path.to_s
    ).and_return("#{other_revision}\trefs/tags/prod\n")
    event = described_class::Event.new(
      name: "push",
      ref: "refs/tags/prod",
      before: revision_before,
      after: revision_after
    )

    expect { described_class.new(event:, runner:, production_path:, staging_path:).run }
      .to raise_error(described_class::CommandError, /remote prod tag/)
    expect(runner).not_to have_received(:run)
  end

  it "loads event revisions from the GitHub event payload" do
    Dir.mktmpdir("atlas-event") do |directory|
      path = Pathname(directory).join("event.json")
      path.write({ "before" => revision_before, "after" => revision_after, "ref" => "refs/heads/main" }.to_json)

      event = described_class.event_from_environment(
        env: { "GITHUB_EVENT_NAME" => "push", "GITHUB_REF" => "refs/heads/main", "GITHUB_EVENT_PATH" => path.to_s }
      )

      expect(event).to have_attributes(name: "push", ref: "refs/heads/main", before: revision_before, after: revision_after)
    end
  end

  it "rejects an event payload whose ref disagrees with GITHUB_REF" do
    Dir.mktmpdir("atlas-event") do |directory|
      path = Pathname(directory).join("event.json")
      path.write({ "ref" => "refs/tags/prod" }.to_json)

      expect do
        described_class.event_from_environment(
          env: { "GITHUB_EVENT_NAME" => "push", "GITHUB_REF" => "refs/heads/main", "GITHUB_EVENT_PATH" => path.to_s }
        )
      end.to raise_error(described_class::CommandError, /does not match/)
    end
  end

  it "rejects a dirty tracked checkout before changing its revision" do
    allow(runner).to receive(:capture).with(
      [ "git", "status", "--porcelain=v1", "--untracked-files=all" ], chdir: production_path.to_s
    ).and_return(" M app/models/example.rb\n")
    event = described_class::Event.new(
      name: "push",
      ref: "refs/tags/prod",
      before: revision_before,
      after: revision_after
    )

    expect { described_class.new(event:, runner:, production_path:, staging_path:).run }
      .to raise_error(Atlas::DeploymentAutomation::CommandError, /working tree is not clean/)
    expect(runner).not_to have_received(:run)
  end

  it "rejects a dirty staging checkout before moving the staging tag" do
    allow(runner).to receive(:capture).with(
      [ "git", "status", "--porcelain=v1", "--untracked-files=all" ], chdir: staging_path.to_s
    ).and_return(" M app/models/example.rb\n")
    event = described_class::Event.new(
      name: "push",
      ref: "refs/heads/main",
      before: revision_before,
      after: revision_after
    )

    expect { described_class.new(event:, runner:, production_path:, staging_path:).run }
      .to raise_error(described_class::CommandError, /working tree is not clean/)
    expect(runner).not_to have_received(:run).with(
      [ "git", "push", "--force-with-lease=refs/tags/staging:#{revision_before}", "origin", "#{revision_after}:refs/tags/staging" ],
      chdir: staging_path.to_s
    )
  end
end
