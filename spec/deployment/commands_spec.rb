require "pathname"

require_relative "../../lib/atlas/deployment"

RSpec.describe Atlas::Deployment::DeployWorkflow do
  let(:runner) { instance_double(Atlas::Deployment::CommandRunner) }
  let(:verifier) { instance_double(Atlas::Deployment::Verifier, verify: true) }
  let(:workflow) { described_class.new(runner:, verifier:) }

  before do
    allow(runner).to receive(:run)
    allow(runner).to receive(:capture).and_return("marker\n")
  end

  it "builds locally, prepares and seeds explicitly for a fresh deployment" do
    workflow.run("fresh")

    expect(runner).to have_received(:run).with(%w[docker compose config --quiet])
    expect(runner).to have_received(:run).with(%w[docker compose build atlas])
    expect(runner).to have_received(:run).with(%w[docker compose up --detach atlas])
    expect(runner).to have_received(:run).with(%w[docker compose exec --no-TTY atlas ./bin/docker-entrypoint ./bin/rails db:prepare])
    expect(runner).to have_received(:run).with(%w[docker compose exec --no-TTY atlas ./bin/docker-entrypoint ./bin/rails db:seed])
    expect(verifier).to have_received(:verify)
  end

  it "provides an update action with the same safe preparation sequence" do
    workflow.run("update")

    expect(runner).to have_received(:capture).twice
    expect(runner).to have_received(:run).with(%w[docker compose config --quiet])
    expect(runner).to have_received(:run).with(%w[docker compose build atlas])
    expect(runner).to have_received(:run).with(%w[docker compose up --detach atlas])
    expect(runner).to have_received(:run).with(%w[docker compose exec --no-TTY atlas ./bin/docker-entrypoint ./bin/rails db:prepare])
    expect(runner).to have_received(:run).with(%w[docker compose exec --no-TTY atlas ./bin/docker-entrypoint ./bin/rails db:seed])
  end

  it "checks persistence across an explicit restart" do
    workflow.run("restart")

    expect(runner).to have_received(:capture).twice
    expect(runner).to have_received(:run).with(%w[docker compose restart atlas])
    expect(verifier).to have_received(:verify)
  end

  it "fails when the restart persistence marker changes" do
    allow(runner).to receive(:capture).and_return("before\n", "after\n")

    expect { workflow.run("restart") }.to raise_error(Atlas::Deployment::CommandError, /persistence marker/)
  end

  it "requires explicit confirmation for rollback operations" do
    expect { workflow.run("rollback") }.to raise_error(ArgumentError, /rollback.*--confirm/)
  end

  it "does not provide an automated restore action" do
    expect { workflow.run("restore") }.to raise_error(ArgumentError, /usage: bin\/deploy/)
  end

  it "selects a rollback image only when explicitly confirmed" do
    allow(runner).to receive(:capture).and_return("atlas-atlas\n")

    workflow.run("rollback", arguments: [ "atlas-atlas:previous", "--confirm" ])

    expect(runner).to have_received(:run).with([ "docker", "image", "inspect", "atlas-atlas:previous" ])
    expect(runner).to have_received(:run).with([ "docker", "tag", "atlas-atlas:previous", "atlas-atlas" ])
    expect(runner).to have_received(:run).with(%w[docker compose up --detach --no-build atlas])
  end
end

RSpec.describe Atlas::Deployment::Verifier do
  let(:runner) { instance_double(Atlas::Deployment::CommandRunner) }
  let(:repository_root) { Pathname.new(__dir__).join("../..").expand_path }
  let(:verifier) { described_class.new(runner:, repository_root:) }

  before do
    allow(runner).to receive(:run)
    allow(runner).to receive(:capture) do |command|
      case command
      when %w[docker compose ps --status running --services]
        "atlas\n"
      when %w[docker compose port atlas 80]
        ""
      when %w[docker compose images -q atlas]
        "sha256:atlas\n"
      when %w[docker compose config]
        "services:\n"
      when %w[git ls-files -z]
        "Dockerfile\0bin/docker-entrypoint\0compose.yaml\0.env.example\0"
      when [ "docker", "compose", "logs", "--no-color", "--tail", "1000", "atlas" ]
        ""
      when [ "docker", "history", "--no-trunc", "sha256:atlas" ]
        "CMD [\"./bin/thrust\"]\n"
      when [ "docker", "compose", "exec", "--no-TTY", "atlas", "sh", "-c", "cat /run/secrets/rails_master_key" ]
        "test-secret\n"
      else
        "ok\n"
      end
    end
  end

  it "checks Compose readiness, HTTPS health/status, and secret hygiene" do
    verifier.verify

    expect(runner).to have_received(:run).with(%w[docker compose config --quiet])
    expect(runner).to have_received(:capture).with(%w[docker compose ps --status running --services])
    expect(runner).to have_received(:capture).with(%w[docker compose port atlas 80])
    expect(runner).to have_received(:capture).with(%w[docker compose config])
    expect(runner).to have_received(:capture).with(
      [ "curl", "--fail", "--silent", "--show-error", "--location", "--header", "Host: atlas.home.arpa", "https://atlas.home.arpa/up" ]
    )
    expect(runner).to have_received(:capture).with(
      [ "curl", "--fail", "--silent", "--show-error", "--location", "--header", "Host: atlas.home.arpa", "https://atlas.home.arpa/status" ]
    )
  end

  it "checks a supplied secret value without matching safe source examples" do
    verifier = described_class.new(
      runner:,
      repository_root:,
      env: { "RAILS_MASTER_KEY" => "test-secret", "ATLAS_HOST" => "atlas.home.arpa" }
    )

    expect { verifier.verify }.not_to raise_error
  end

  it "rejects a Rails master key in rendered Compose configuration" do
    allow(runner).to receive(:capture).with(%w[docker compose config]).and_return("RAILS_MASTER_KEY: test-secret\n")
    verifier = described_class.new(
      runner:,
      repository_root:,
      env: { "RAILS_MASTER_KEY" => "test-secret", "ATLAS_HOST" => "atlas.home.arpa" }
    )

    expect { verifier.verify }.to raise_error(Atlas::Deployment::CommandError, /rendered Compose configuration/)
  end
end
