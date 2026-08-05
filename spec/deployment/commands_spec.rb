require "json"
require "pathname"

require_relative "../../lib/atlas/deployment"

RSpec.describe Atlas::Deployment::ComposeReadinessWaiter do
  let(:runner) { instance_double(Atlas::Deployment::CommandRunner) }
  let(:status_command) { %w[docker compose ps --format json --all atlas] }
  let(:logs_command) { %w[docker compose logs --no-color --tail 200 atlas] }

  def compose_status(attributes)
    attributes.to_json
  end

  it "uses bounded production defaults" do
    expect(described_class::DEFAULT_TIMEOUT).to eq(120)
    expect(described_class::DEFAULT_POLLING_INTERVAL).to eq(2)
    expect(described_class::LOG_TAIL_LINES).to eq(200)
  end

  it "returns immediately when the running service is healthy" do
    allow(runner).to receive(:capture).with(status_command).and_return(
      compose_status("ID" => "container-id", "Service" => "atlas", "State" => "running", "Health" => "healthy", "Status" => "Up 1 minute", "ExitCode" => 0)
    )
    sleeper = instance_double(Proc)
    allow(sleeper).to receive(:call)

    result = described_class.new(runner:, sleeper:).wait

    expect(result).to be(true)
    expect(runner).to have_received(:capture).once.with(status_command)
    expect(sleeper).not_to have_received(:call)
  end

  it "polls a starting service until it becomes healthy" do
    current_time = 0.0
    clock = -> { current_time }
    sleeper = ->(duration) { current_time += duration }
    allow(runner).to receive(:capture).with(status_command).and_return(
      compose_status("ID" => "container-id", "Service" => "atlas", "State" => "running", "Health" => "starting", "Status" => "Up 1 second", "ExitCode" => 0),
      compose_status("ID" => "container-id", "Service" => "atlas", "State" => "running", "Health" => "healthy", "Status" => "Up 3 seconds", "ExitCode" => 0)
    )

    expect(described_class.new(runner:, clock:, sleeper:).wait).to be(true)
    expect(runner).to have_received(:capture).twice.with(status_command)
  end

  it "fails immediately for an unhealthy service with bounded diagnostics" do
    logs = (1..250).map { |line| "log-#{line}" }.join("\n")
    allow(runner).to receive(:capture).with(status_command).and_return(
      compose_status("ID" => "container-id", "Service" => "atlas", "State" => "running", "Health" => "unhealthy", "Status" => "Up 1 minute (unhealthy)", "ExitCode" => 0)
    )
    allow(runner).to receive(:capture).with(logs_command).and_return(logs)

    error = nil
    expect { described_class.new(runner:).wait }.to raise_error(Atlas::Deployment::CommandError) { |raised| error = raised }

    expect(error.message).to include("unhealthy", '"ID":"container-id"', '"Health":"unhealthy"', "log-51", "log-250")
    expect(error.message).not_to include("log-50")
    expect(error.message.lines.grep(/^log-/).length).to eq(200)
    expect(runner).to have_received(:capture).with(logs_command)
  end

  it "fails immediately when the container has exited" do
    allow(runner).to receive(:capture).with(status_command).and_return(
      compose_status("ID" => "container-id", "Service" => "atlas", "State" => "exited", "Health" => "", "Status" => "Exited (1)", "ExitCode" => 1)
    )
    allow(runner).to receive(:capture).with(logs_command).and_return("exit log")

    expect { described_class.new(runner:).wait }.to raise_error(Atlas::Deployment::CommandError, /exited.*ExitCode.*1.*exit log/m)
  end

  it "fails at the bounded deadline for a missing service" do
    current_time = 0.0
    clock = -> { current_time }
    sleeper = ->(duration) { current_time += duration }
    allow(runner).to receive(:capture).with(status_command).and_return("", "", "")
    allow(runner).to receive(:capture).with(logs_command).and_return("last log")

    error = nil
    expect do
      described_class.new(runner:, timeout: 4, polling_interval: 2, clock:, sleeper:).wait
    end.to raise_error(Atlas::Deployment::CommandError) { |raised| error = raised }

    expect(error.message).to include("timed out", "last log")
    expect(runner).to have_received(:capture).exactly(3).times.with(status_command)
  end

  it "uses injected timeout, polling, clock, and sleeper values" do
    current_time = 10.0
    slept = []
    clock = -> { current_time }
    sleeper = ->(duration) { slept << duration; current_time += duration }
    allow(runner).to receive(:capture).with(status_command).and_return(
      compose_status("State" => "running", "Health" => "starting"),
      compose_status("State" => "running", "Health" => "healthy")
    )

    described_class.new(runner:, timeout: 1, polling_interval: 0.25, clock:, sleeper:).wait

    expect(slept).to eq([ 0.25 ])
  end
end

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
      when %w[docker compose config --format json]
        { "services" => { "atlas" => { "expose" => [ 80 ] } } }.to_json
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
    expect(runner).to have_received(:capture).with(%w[docker compose config --format json])
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

  it "accepts an exposed atlas port without a published host mapping" do
    expect { verifier.verify }.not_to raise_error
  end

  it "accepts a null published mapping for atlas port 80" do
    allow(runner).to receive(:capture).with(%w[docker compose config --format json]).and_return(
      {
        "services" => {
          "atlas" => {
            "ports" => [ { "target" => 80, "published" => nil, "protocol" => "tcp", "mode" => "ingress" } ]
          }
        }
      }.to_json
    )

    expect { verifier.verify }.not_to raise_error
  end

  it "rejects a concrete published host mapping for atlas port 80" do
    allow(runner).to receive(:capture).with(%w[docker compose config --format json]).and_return(
      {
        "services" => {
          "atlas" => {
            "ports" => [ { "target" => 80, "published" => 8080, "protocol" => "tcp", "mode" => "ingress" } ]
          }
        }
      }.to_json
    )

    expect { verifier.verify }.to raise_error(Atlas::Deployment::CommandError, /unexpected host port.*8080/)
  end

  it "preserves failures from the rendered Compose configuration command" do
    allow(runner).to receive(:capture).with(%w[docker compose config --format json]).and_raise(
      Atlas::Deployment::CommandError, "command failed (1): docker compose config --format json"
    )

    expect { verifier.verify }.to raise_error(Atlas::Deployment::CommandError, /command failed.*config --format json/)
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
