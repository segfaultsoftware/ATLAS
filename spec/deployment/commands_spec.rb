require "json"
require "pathname"

require_relative "../../lib/atlas/deployment"

RSpec.describe Atlas::Deployment::ReadinessWaiter do
  let(:runner) { instance_double(Atlas::Deployment::CommandRunner) }
  let(:time) { [ 0.0 ] }
  let(:sleep_calls) { [] }
  let(:clock) { -> { time.first } }
  let(:sleeper) do
    ->(duration) do
      sleep_calls << duration
      time[0] += duration
    end
  end
  let(:waiter) { described_class.new(runner:, clock:, sleeper:) }

  def status_command
    %w[docker compose ps --format json --all atlas]
  end

  def logs_command
    %w[docker compose logs --no-color --tail 200 atlas]
  end

  def inspect_command
    [ "docker", "inspect", "--format", "{{json .State.Health}}", "container-id" ]
  end

  def status(state:, health: nil, status: "", exit_code: 0, id: "container-id", service: "atlas")
    {
      "ID" => id,
      "Service" => service,
      "State" => state,
      "Health" => health,
      "Status" => status,
      "ExitCode" => exit_code
    }.compact.to_json
  end

  it "returns immediately when the service is running and healthy" do
    allow(runner).to receive(:capture).with(status_command).and_return(status(state: "running", health: "healthy"))

    expect(waiter.wait).to be(true)
    expect(sleep_calls).to be_empty
  end

  it "polls a starting service until it becomes healthy" do
    allow(runner).to receive(:capture).with(status_command).and_return(
      status(state: "running", health: "starting"),
      status(state: "running", health: "healthy")
    )

    expect(waiter.wait).to be(true)
    expect(sleep_calls).to eq([ 2 ])
    expect(runner).to have_received(:capture).with(status_command).twice
  end

  it "parses JSON Lines and selects the atlas service" do
    output = [
      status(state: "running", health: "starting", service: "other"),
      status(state: "running", health: "healthy")
    ].join("\n")
    allow(runner).to receive(:capture).with(status_command).and_return(output)

    expect(waiter.wait).to be(true)
  end

  it "fails immediately for an unhealthy service with bounded diagnostics" do
    allow(runner).to receive(:capture).with(status_command).and_return(
      status(state: "running", health: "unhealthy", status: "Up 2 minutes")
    )
    allow(runner).to receive(:capture).with(inspect_command).and_return('{"Status":"unhealthy"}')
    allow(runner).to receive(:capture).with(logs_command).and_return("recent log\n")

    expect { waiter.wait }.to raise_error(Atlas::Deployment::CommandError) do |error|
      expect(error.message).to include("unhealthy")
      expect(error.message).to include("Up 2 minutes")
      expect(error.message).to include("recent log")
    end
    expect(sleep_calls).to be_empty
  end

  it "fails immediately for an exited service" do
    allow(runner).to receive(:capture).with(status_command).and_return(
      status(state: "exited", status: "Exited (1)", exit_code: 1)
    )
    allow(runner).to receive(:capture).with(inspect_command).and_return('{"Status":"exited"}')
    allow(runner).to receive(:capture).with(logs_command).and_return("crash log\n")

    expect { waiter.wait }.to raise_error(Atlas::Deployment::CommandError, /exited.*ExitCode.*1.*crash log/m)
    expect(sleep_calls).to be_empty
  end

  it "times out for an unavailable service with at most 200 log lines" do
    allow(runner).to receive(:capture).with(status_command).and_return("")
    allow(runner).to receive(:capture).with(logs_command).and_return((1..250).map { |line| "line #{line}" }.join("\n"))
    waiter = described_class.new(runner:, timeout: 5, poll_interval: 2, clock:, sleeper:)

    expect { waiter.wait }.to raise_error(Atlas::Deployment::CommandError) do |error|
      expect(error.message).to include("timed out")
      expect(error.message).to include("line 200")
      expect(error.message).not_to include("line 201")
    end
    expect(sleep_calls).to eq([ 2, 2, 1 ])
  end

  it "uses configurable timeout and polling defaults" do
    expect(described_class::DEFAULT_TIMEOUT).to eq(120)
    expect(described_class::DEFAULT_POLL_INTERVAL).to eq(2)

    expect { described_class.new(runner:, timeout: -1) }.to raise_error(ArgumentError)
    expect { described_class.new(runner:, poll_interval: 0) }.to raise_error(ArgumentError)
  end

  it "includes a command failure in the bounded timeout diagnostic" do
    command_error = Atlas::Deployment::CommandError.new("status unavailable")
    allow(runner).to receive(:capture).with(status_command).and_raise(command_error)
    allow(runner).to receive(:capture).with(logs_command).and_return("logs\n")
    waiter = described_class.new(runner:, timeout: 0, clock:, sleeper:)

    expect { waiter.wait }.to raise_error(Atlas::Deployment::CommandError, /status unavailable.*logs/m)
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
