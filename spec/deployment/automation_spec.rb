require "json"
require "pathname"
require "tmpdir"
require "fileutils"

require_relative "../../lib/atlas/deployment_automation"

RSpec.describe Atlas::DeploymentAutomation do
  let(:before_revision) { "1" * 40 }
  let(:after_revision) { "2" * 40 }
  let(:checkout_root) { Pathname(Dir.mktmpdir("atlas-deployment-automation")) }
  let(:production_path) { checkout_root.join("production") }
  let(:staging_path) { checkout_root.join("staging") }
  let(:runner) { instance_double(Atlas::DeploymentAutomation::CommandRunner) }

  before do
    production_path.join(".git").mkpath
    staging_path.join(".git").mkpath
    @staging_revision = before_revision

    allow(runner).to receive(:run) do |command, chdir:, environment: {}|
      @staging_revision = after_revision if command.first(2) == [ "git", "push" ]
    end
    allow(runner).to receive(:capture) do |command, chdir:|
      case command
      when [ "git", "ls-remote", "origin", "refs/tags/prod", "refs/tags/prod^{}" ]
        "#{after_revision}\trefs/tags/prod\n"
      when [ "git", "ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}" ]
        "#{@staging_revision}\trefs/tags/staging\n"
      when [ "git", "ls-remote", "origin", "refs/heads/main" ]
        "#{after_revision}\trefs/heads/main\n"
      when [ "git", "status", "--porcelain=v1", "--untracked-files=all" ]
        ""
      when [ "git", "fetch", "--no-tags", "origin", after_revision ]
        ""
      when [ "git", "rev-parse", "HEAD" ]
        "#{after_revision}\n"
      else
        raise "unexpected capture: #{command.inspect} in #{chdir}"
      end
    end
  end

  after do
    FileUtils.remove_entry(checkout_root) if checkout_root.exist?
  end

  def event(ref:, name: "push", before: before_revision, after: after_revision, **attributes)
    described_class::Event.new(name:, ref:, before:, after:, **attributes)
  end

  it "ignores unsupported events and refs without touching a checkout" do
    result = described_class.new(
      event: event(name: "pull_request", ref: "refs/heads/main"),
      runner:,
      production_path:,
      staging_path:
    ).run

    expect(result).to include(status: :noop, reason: :unsupported_event)
    expect(runner).not_to have_received(:capture)
    expect(runner).not_to have_received(:run)
  end

  it "ignores unrelated push refs" do
    result = described_class.new(
      event: event(ref: "refs/heads/feature"),
      runner:,
      production_path:,
      staging_path:
    ).run

    expect(result).to include(status: :noop, reason: :unrelated_ref)
    expect(runner).not_to have_received(:capture)
    expect(runner).not_to have_received(:run)
  end

  it "deploys the current production tag after synchronizing a detached checkout" do
    result = described_class.new(
      event: event(ref: "refs/tags/prod"),
      runner:,
      production_path:,
      staging_path:
    ).run

    expect(result).to include(status: :deployed, environment: :production, revision: after_revision)
    expect(runner).to have_received(:run).with(
      [ "git", "fetch", "--no-tags", "origin", after_revision ], chdir: production_path.to_s
    ).ordered
    expect(runner).to have_received(:run).with(
      [ "git", "checkout", "--detach", "--force", after_revision ], chdir: production_path.to_s
    ).ordered
    expect(runner).to have_received(:run).with(
      [ "bin/deploy", "update" ], chdir: production_path.to_s, environment: { "ATLAS_HOST" => "atlas.home.arpa" }
    ).ordered
    expect(runner).to have_received(:run).with(
      [ "bin/verify-deployment" ], chdir: production_path.to_s, environment: { "ATLAS_HOST" => "atlas.home.arpa" }
    ).ordered
  end

  it "rejects a production event when the tag moved elsewhere" do
    other_revision = "3" * 40
    allow(runner).to receive(:capture).with(
      [ "git", "ls-remote", "origin", "refs/tags/prod", "refs/tags/prod^{}" ], chdir: production_path.to_s
    ).and_return("#{other_revision}\trefs/tags/prod\n")

    expect { described_class.new(event: event(ref: "refs/tags/prod"), runner:, production_path:, staging_path:).run }
      .to raise_error(described_class::CommandError, /remote prod tag/)
    expect(runner).not_to have_received(:run)
  end

  it "leaves an absent staging tag unchanged" do
    allow(runner).to receive(:capture).with(
      [ "git", "ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}" ], chdir: staging_path.to_s
    ).and_return("")

    result = described_class.new(event: event(ref: "refs/heads/main"), runner:, production_path:, staging_path:).run

    expect(result).to include(status: :noop, reason: :staging_tag_absent)
    expect(runner).not_to have_received(:run)
  end

  it "preserves an intentionally pinned staging tag" do
    pinned_revision = "3" * 40
    allow(runner).to receive(:capture).with(
      [ "git", "ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}" ], chdir: staging_path.to_s
    ).and_return("#{pinned_revision}\trefs/tags/staging\n")

    result = described_class.new(event: event(ref: "refs/heads/main"), runner:, production_path:, staging_path:).run

    expect(result).to include(status: :noop, reason: :staging_pinned)
    expect(runner).not_to have_received(:run)
  end

  it "advances tracking staging with a compare-and-swap before deploying" do
    result = described_class.new(event: event(ref: "refs/heads/main"), runner:, production_path:, staging_path:).run

    expect(result).to include(status: :deployed, environment: :staging, revision: after_revision)
    expect(runner).to have_received(:run).with(
      [ "git", "push", "--force-with-lease=refs/tags/staging:#{before_revision}", "origin", "#{after_revision}:refs/tags/staging" ],
      chdir: staging_path.to_s
    ).ordered
    expect(runner).to have_received(:run).with(
      [ "bin/deploy", "update" ], chdir: staging_path.to_s, environment: { "ATLAS_HOST" => "atlas-staging.home.arpa" }
    ).ordered
  end

  it "uses the tag object as the compare-and-swap lease for annotated tags" do
    tag_object = "9" * 40
    allow(runner).to receive(:capture).with(
      [ "git", "ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}" ], chdir: staging_path.to_s
    ).and_return(
      "#{tag_object}\trefs/tags/staging\n#{before_revision}\trefs/tags/staging^{}\n",
      "#{tag_object}\trefs/tags/staging\n#{after_revision}\trefs/tags/staging^{}\n"
    )

    described_class.new(event: event(ref: "refs/heads/main"), runner:, production_path:, staging_path:).run

    expect(runner).to have_received(:run).with(
      [ "git", "push", "--force-with-lease=refs/tags/staging:#{tag_object}", "origin", "#{after_revision}:refs/tags/staging" ],
      chdir: staging_path.to_s
    )
  end

  it "verifies an annotated production tag by its peeled commit" do
    tag_object = "9" * 40
    allow(runner).to receive(:capture).with(
      [ "git", "ls-remote", "origin", "refs/tags/prod", "refs/tags/prod^{}" ], chdir: production_path.to_s
    ).and_return("#{tag_object}\trefs/tags/prod\n#{after_revision}\trefs/tags/prod^{}\n")

    result = described_class.new(event: event(ref: "refs/tags/prod"), runner:, production_path:, staging_path:).run

    expect(result).to include(status: :deployed, environment: :production, revision: after_revision)
  end

  it "deploys safely when staging already points at the event revision" do
    allow(runner).to receive(:capture).with(
      [ "git", "ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}" ], chdir: staging_path.to_s
    ).and_return("#{after_revision}\trefs/tags/staging\n")

    result = described_class.new(event: event(ref: "refs/heads/main"), runner:, production_path:, staging_path:).run

    expect(result).to include(status: :deployed, environment: :staging, revision: after_revision)
    expect(runner).not_to have_received(:run).with(a_collection_including("git", "push"), anything)
  end

  it "does not advance staging for a delayed main event" do
    current_main = "4" * 40
    allow(runner).to receive(:capture).with(
      [ "git", "ls-remote", "origin", "refs/heads/main" ], chdir: staging_path.to_s
    ).and_return("#{current_main}\trefs/heads/main\n")

    result = described_class.new(event: event(ref: "refs/heads/main"), runner:, production_path:, staging_path:).run

    expect(result).to include(status: :noop, reason: :stale_main_event)
    expect(runner).not_to have_received(:run)
  end

  it "fails visibly and does not deploy when compare-and-swap loses a race" do
    allow(runner).to receive(:run).with(
      [ "git", "push", "--force-with-lease=refs/tags/staging:#{before_revision}", "origin", "#{after_revision}:refs/tags/staging" ],
      chdir: staging_path.to_s
    ).and_raise(described_class::CommandError, "lease rejected; token=secret")

    expect { described_class.new(event: event(ref: "refs/heads/main"), runner:, production_path:, staging_path:).run }
      .to raise_error(described_class::CommandError) { |error| expect(error.message).not_to include("secret") }
    expect(runner).not_to have_received(:run).with([ "bin/deploy", "update" ], chdir: staging_path.to_s, environment: { "ATLAS_HOST" => "atlas-staging.home.arpa" })
  end

  it "does not deploy when the post-push staging ref is not the requested revision" do
    allow(runner).to receive(:capture).with(
      [ "git", "ls-remote", "origin", "refs/tags/staging", "refs/tags/staging^{}" ], chdir: staging_path.to_s
    ).and_return(
      "#{before_revision}\trefs/tags/staging\n",
      "#{"3" * 40}\trefs/tags/staging\n"
    )

    expect { described_class.new(event: event(ref: "refs/heads/main"), runner:, production_path:, staging_path:).run }
      .to raise_error(described_class::CommandError, /could not be verified/)
    expect(runner).not_to have_received(:run).with([ "bin/deploy", "update" ], chdir: staging_path.to_s, environment: { "ATLAS_HOST" => "atlas-staging.home.arpa" })
  end

  it "leaves the staging tag advanced when deployment fails after a successful tag move" do
    allow(runner).to receive(:run).with(
      [ "bin/deploy", "update" ], chdir: staging_path.to_s, environment: { "ATLAS_HOST" => "atlas-staging.home.arpa" }
    )
      .and_raise(described_class::CommandError, "deployment failed; token=secret")

    expect { described_class.new(event: event(ref: "refs/heads/main"), runner:, production_path:, staging_path:).run }
      .to raise_error(described_class::CommandError) { |error| expect(error.message).not_to include("secret") }
    expect(@staging_revision).to eq(after_revision)
    expect(runner).not_to have_received(:run).with(
      [ "bin/verify-deployment" ], chdir: staging_path.to_s, environment: { "ATLAS_HOST" => "atlas-staging.home.arpa" }
    )
  end

  it "rejects an unsafe tracked working tree before changing its revision" do
    allow(runner).to receive(:capture).with(
      [ "git", "status", "--porcelain=v1", "--untracked-files=all" ], chdir: production_path.to_s
    ).and_return(" M tracked.rb\n")

    expect { described_class.new(event: event(ref: "refs/tags/prod"), runner:, production_path:, staging_path:).run }
      .to raise_error(described_class::CommandError, /working tree is not clean/)
    expect(runner).not_to have_received(:run)
  end

  it "preserves ignored environment and storage files during checkout" do
    result = described_class.new(event: event(ref: "refs/tags/prod"), runner:, production_path:, staging_path:).run

    expect(result).to include(status: :deployed)
    expect(runner).to have_received(:run).with(
      [ "git", "checkout", "--detach", "--force", after_revision ], chdir: production_path.to_s
    )
  end

  it "loads and validates the GitHub event payload" do
    Dir.mktmpdir("atlas-event") do |directory|
      path = Pathname(directory).join("event.json")
      path.write({ "before" => before_revision, "after" => after_revision, "ref" => "refs/heads/main" }.to_json)

      parsed = described_class.event_from_environment(
        env: { "GITHUB_EVENT_NAME" => "push", "GITHUB_REF" => "refs/heads/main", "GITHUB_EVENT_PATH" => path.to_s }
      )

      expect(parsed).to have_attributes(name: "push", ref: "refs/heads/main", before: before_revision, after: after_revision)
    end
  end

  it "rejects a payload whose ref disagrees with GITHUB_REF" do
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
end
