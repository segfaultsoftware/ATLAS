require "json"
require "pathname"
require "rbconfig"
require "tempfile"

require_relative "../../lib/atlas/deployment"

RSpec.describe Atlas::Deployment::CommandRunner do
  it "bounds stdout and stderr while draining the child process" do
    runner = described_class.new
    output = runner.capture_bounded(
      [ RbConfig.ruby, "-e", 'STDOUT.write("x" * 100_000)' ],
      max_bytes: 128,
      max_lines: 2
    )

    expect(output).to eq("x" * 128)
  end

  it "bounds command failure output" do
    runner = described_class.new

    expect do
      runner.capture_bounded(
        [ RbConfig.ruby, "-e", 'STDERR.write("password=secret" * 1_000); exit 3' ],
        max_bytes: 128,
        max_lines: 2
      )
    end.to raise_error(Atlas::Deployment::CommandError) do |error|
      expect(error.message.bytesize).to be < 300
    end
  end
end

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

  before do
    allow(runner).to receive(:capture_bounded) do |command, max_bytes:, max_lines:|
      runner.capture(command)
    end
  end

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

  it "redacts configured and credential-shaped secrets from every diagnostic source" do
    master_key = "rails-master-key-123"
    status_output = status(
      state: "running",
      health: "unhealthy",
      status: "password=plain-password RAILS_MASTER_KEY=#{master_key}"
    )
    health_output = <<~JSON
      {"Status":"unhealthy","password":"health-password","notes":"line one\nline two"}
    JSON
    log_output = <<~LOG
      RAILS_MASTER_KEY=#{master_key}
      password: log-password
      Authorization: Bearer bearer-token
      multiline_secret: |
        first-line
        second-line
    LOG
    allow(runner).to receive(:capture).with(status_command).and_return(status_output)
    allow(runner).to receive(:capture).with(inspect_command).and_return(health_output)
    allow(runner).to receive(:capture).with(logs_command).and_return(log_output)
    waiter = described_class.new(runner:, clock:, sleeper:, secret_values: [ master_key ])

    expect { waiter.wait }.to raise_error(Atlas::Deployment::CommandError) do |error|
      expect(error.message).to include("[REDACTED]")
      expect(error.message).not_to include(master_key)
      expect(error.message).not_to include("plain-password")
      expect(error.message).not_to include("health-password")
      expect(error.message).not_to include("log-password")
      expect(error.message).not_to include("bearer-token")
      expect(error.message).not_to include("first-line")
      expect(error.message).not_to include("second-line")
    end
  end

  it "caps status, health, and log diagnostics by lines and bytes before assembly" do
    status_output = status(
      state: "running",
      health: "unhealthy",
      status: "status-start #{"s" * 10_000} status-end"
    )
    health_output = (1..100).map { |line| "health-#{line} #{"h" * 200}" }.join("\n")
    log_output = (1..250).map { |line| "log-#{line}" }.join("\n")
    allow(runner).to receive(:capture).with(status_command).and_return(status_output)
    allow(runner).to receive(:capture).with(inspect_command).and_return(health_output)
    allow(runner).to receive(:capture).with(logs_command).and_return(log_output)

    expect { waiter.wait }.to raise_error(Atlas::Deployment::CommandError) do |error|
      expect(error.message).to include("status-start")
      expect(error.message).not_to include("status-end")
      expect(error.message).to include("health-1")
      expect(error.message).not_to include("health-100")
      expect(error.message).to include("log-200")
      expect(error.message).not_to include("log-201")
      expect(error.message.bytesize).to be < 30_000
    end
  end

  it "collects failure diagnostics once after polling reaches the deadline" do
    allow(runner).to receive(:capture).with(status_command).and_return("")
    allow(runner).to receive(:capture).with(logs_command).and_return("logs\n")
    waiter = described_class.new(runner:, timeout: 5, poll_interval: 2, clock:, sleeper:)

    expect { waiter.wait }.to raise_error(Atlas::Deployment::CommandError)
    expect(runner).to have_received(:capture).with(logs_command).once
  end

  it "redacts secrets from status and log command failures" do
    master_key = "rails-master-key-123"
    allow(runner).to receive(:capture).with(status_command).and_raise(
      Atlas::Deployment::CommandError,
      "status failed: password=status-password RAILS_MASTER_KEY=#{master_key}"
    )
    allow(runner).to receive(:capture).with(logs_command).and_raise(
      Atlas::Deployment::CommandError,
      "logs failed: client_secret=client-secret"
    )
    waiter = described_class.new(runner:, timeout: 0, clock:, sleeper:, secret_values: [ master_key ])

    expect { waiter.wait }.to raise_error(Atlas::Deployment::CommandError) do |error|
      expect(error.message).not_to include(master_key)
      expect(error.message).not_to include("status-password")
      expect(error.message).not_to include("client-secret")
      expect(error.message).to include("[REDACTED]")
    end
  end
end

RSpec.describe Atlas::Deployment::DeployWorkflow do
  let(:runner) { instance_double(Atlas::Deployment::CommandRunner) }
  let(:verifier) { instance_double(Atlas::Deployment::Verifier, verify: true) }
  let(:readiness_waiter) { instance_double(Atlas::Deployment::ReadinessWaiter, wait: true) }
  let(:workflow) { described_class.new(runner:, verifier:, readiness_waiter:) }

  before do
    allow(runner).to receive(:run)
    allow(runner).to receive(:capture).and_return("marker\n")
  end

  it "uses entrypoint preparation and waits for readiness before seeding and verifying a fresh deployment" do
    events = []
    allow(runner).to receive(:run) { |command| events << command }
    allow(readiness_waiter).to receive(:wait) { events << :readiness }
    allow(verifier).to receive(:verify) { events << :verify }

    workflow.run("fresh")

    expect(events).to eq([
      %w[docker compose config --quiet],
      %w[docker compose build atlas],
      %w[docker compose up --detach atlas],
      :readiness,
      %w[docker compose exec --no-TTY atlas ./bin/docker-entrypoint ./bin/rails db:seed],
      :verify
    ])
  end

  it "uses entrypoint preparation and waits for readiness before seeding and verifying an update" do
    events = []
    allow(runner).to receive(:run) { |command| events << command }
    allow(runner).to receive(:capture) { events << :capture; "marker\n" }
    allow(readiness_waiter).to receive(:wait) { events << :readiness }
    allow(verifier).to receive(:verify) { events << :verify }

    workflow.run("update")

    expect(events).to eq([
      :capture,
      %w[docker compose config --quiet],
      %w[docker compose build atlas],
      %w[docker compose up --detach atlas],
      :readiness,
      %w[docker compose exec --no-TTY atlas ./bin/docker-entrypoint ./bin/rails db:seed],
      :verify,
      :capture
    ])
  end

  it "does not seed or verify a fresh deployment when readiness fails" do
    readiness_error = Atlas::Deployment::CommandError.new("Compose readiness failed: timed out")
    allow(readiness_waiter).to receive(:wait).and_raise(readiness_error)

    expect { workflow.run("fresh") }.to raise_error(readiness_error)
    expect(runner).not_to have_received(:run).with(%w[docker compose exec --no-TTY atlas ./bin/docker-entrypoint ./bin/rails db:seed])
    expect(verifier).not_to have_received(:verify)
  end

  it "does not seed or verify an update when readiness fails" do
    readiness_error = Atlas::Deployment::CommandError.new("Compose readiness failed: timed out")
    allow(readiness_waiter).to receive(:wait).and_raise(readiness_error)

    expect { workflow.run("update") }.to raise_error(readiness_error)
    expect(runner).not_to have_received(:run).with(%w[docker compose exec --no-TTY atlas ./bin/docker-entrypoint ./bin/rails db:seed])
    expect(verifier).not_to have_received(:verify)
    expect(runner).to have_received(:capture).once
  end

  it "prepares explicitly before a standalone seed without waiting for readiness" do
    events = []
    allow(runner).to receive(:run) { |command| events << command }
    allow(verifier).to receive(:verify) { events << :verify }

    workflow.run("seed")

    expect(events).to eq([
      %w[docker compose exec --no-TTY atlas ./bin/docker-entrypoint ./bin/rails db:prepare],
      %w[docker compose exec --no-TTY atlas ./bin/docker-entrypoint ./bin/rails db:seed],
      :verify
    ])
    expect(readiness_waiter).not_to have_received(:wait)
  end

  it "checks persistence across an explicit restart" do
    workflow.run("restart")

    expect(runner).to have_received(:capture).twice
    expect(runner).to have_received(:run).with(%w[docker compose restart atlas])
    expect(readiness_waiter).to have_received(:wait)
    expect(verifier).to have_received(:verify)
  end

  it "waits for readiness before verification while preserving marker ordering" do
    expect(runner).to receive(:capture).and_return("marker\n").ordered
    expect(runner).to receive(:run).with(%w[docker compose restart atlas]).ordered
    expect(readiness_waiter).to receive(:wait).ordered
    expect(verifier).to receive(:verify).ordered
    expect(runner).to receive(:capture).and_return("marker\n").ordered

    workflow.run("restart")
  end

  it "does not verify or compare the marker when readiness fails" do
    readiness_error = Atlas::Deployment::CommandError.new("Compose readiness failed: timed out")
    allow(readiness_waiter).to receive(:wait).and_raise(readiness_error)

    expect { workflow.run("restart") }.to raise_error(readiness_error)
    expect(verifier).not_to have_received(:verify)
    expect(runner).to have_received(:capture).once
  end

  it "passes the configured Rails master key into default readiness diagnostics" do
    master_key = "rails-master-key-123"
    environment = { "RAILS_MASTER_KEY" => master_key, "ATLAS_HOST" => "atlas.home.arpa" }
    allow(runner).to receive(:capture_bounded) do |command, max_bytes:, max_lines:|
      runner.capture(command)
    end
    allow(runner).to receive(:capture) do |command|
      case command
      when %w[docker compose ps --format json --all atlas]
        { "ID" => "container-id", "Service" => "atlas", "State" => "running", "Health" => "unhealthy" }.to_json
      when [ "docker", "inspect", "--format", "{{json .State.Health}}", "container-id" ]
        "password=#{master_key}\n"
      when %w[docker compose logs --no-color --tail 200 atlas]
        "RAILS_MASTER_KEY=#{master_key}\n"
      else
        "marker\n"
      end
    end
    workflow = described_class.new(runner:, verifier:, env: environment, readiness_timeout: 0)

    expect { workflow.run("restart") }.to raise_error(Atlas::Deployment::CommandError) do |error|
      expect(error.message).not_to include(master_key)
    end
    expect(verifier).not_to have_received(:verify)
  end

  it "redacts the configured Rails master key file from default readiness diagnostics" do
    secret = Tempfile.new("atlas-master-key")
    secret.write("file-master-key\n")
    secret.flush
    environment = { "RAILS_MASTER_KEY_FILE" => secret.path, "ATLAS_HOST" => "atlas.home.arpa" }
    allow(runner).to receive(:capture_bounded) do |command, max_bytes:, max_lines:|
      runner.capture(command)
    end
    allow(runner).to receive(:capture) do |command|
      case command
      when %w[docker compose ps --format json --all atlas]
        { "ID" => "container-id", "Service" => "atlas", "State" => "running", "Health" => "unhealthy" }.to_json
      when [ "docker", "inspect", "--format", "{{json .State.Health}}", "container-id" ]
        "unhealthy\n"
      when %w[docker compose logs --no-color --tail 200 atlas]
        "file-master-key\n"
      else
        "marker\n"
      end
    end
    workflow = described_class.new(runner:, verifier:, env: environment, readiness_timeout: 0)

    expect { workflow.run("fresh") }.to raise_error(Atlas::Deployment::CommandError) do |error|
      expect(error.message).to include("[REDACTED]")
      expect(error.message).not_to include("file-master-key")
    end
    expect(verifier).not_to have_received(:verify)
  ensure
    secret&.close!
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

  it "waits for readiness before verifying a rollback" do
    events = []
    allow(runner).to receive(:run) { |command| events << command }
    allow(runner).to receive(:capture) do |command|
      events << :capture
      command == %w[docker compose config --images] ? "atlas-atlas\n" : "marker\n"
    end
    allow(readiness_waiter).to receive(:wait) { events << :readiness }
    allow(verifier).to receive(:verify) { events << :verify }

    workflow.run("rollback", arguments: [ "atlas-atlas:previous", "--confirm" ])

    expect(events).to eq([
      %w[docker compose config --quiet],
      [ "docker", "image", "inspect", "atlas-atlas:previous" ],
      :capture,
      [ "docker", "tag", "atlas-atlas:previous", "atlas-atlas" ],
      %w[docker compose up --detach --no-build atlas],
      :readiness,
      :verify
    ])
  end

  it "does not verify a rollback when readiness fails" do
    allow(runner).to receive(:capture).and_return("atlas-atlas\n")
    readiness_error = Atlas::Deployment::CommandError.new("Compose readiness failed: timed out")
    allow(readiness_waiter).to receive(:wait).and_raise(readiness_error)

    expect { workflow.run("rollback", arguments: [ "atlas-atlas:previous", "--confirm" ]) }.to raise_error(readiness_error)
    expect(verifier).not_to have_received(:verify)
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
      when %w[docker compose ps -q atlas]
        "atlas-container\n"
      when [ "docker", "inspect", "--format", "{{.Image}}", "atlas-container" ]
        "sha256:atlas-runtime\n"
      when %w[docker compose config]
        "services:\n"
      when %w[git ls-files -z]
        "Dockerfile\0bin/docker-entrypoint\0compose.yaml\0.env.example\0"
      when [ "docker", "compose", "logs", "--no-color", "--tail", "1000", "atlas" ]
        ""
      when [ "docker", "history", "--no-trunc", "sha256:atlas-runtime" ]
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
    expect(runner).to have_received(:capture).with(%w[docker compose ps -q atlas])
    expect(runner).to have_received(:capture).with(
      [ "docker", "inspect", "--format", "{{.Image}}", "atlas-container" ]
    )
    expect(runner).to have_received(:capture).with(
      [ "docker", "history", "--no-trunc", "sha256:atlas-runtime" ]
    )
    expect(runner).to have_received(:capture).with(
      [ "docker", "compose", "logs", "--no-color", "--tail", "1000", "atlas" ]
    )
    expect(runner).not_to have_received(:capture).with(%w[docker compose images -q atlas])
  end

  it "rejects a missing running atlas container without skipping secret checks" do
    allow(runner).to receive(:capture).with(%w[docker compose ps -q atlas]).and_return("")

    expect { verifier.verify }.to raise_error(Atlas::Deployment::CommandError, /exactly one running atlas container.*found 0/i)
    expect(runner).not_to have_received(:capture).with(array_including("inspect"))
    expect(runner).not_to have_received(:capture).with(array_including("history"))
  end

  it "rejects ambiguous running atlas containers with a bounded diagnostic" do
    first_container = "a" * 64
    second_container = "b" * 64
    allow(runner).to receive(:capture).with(%w[docker compose ps -q atlas]).and_return(
      "#{first_container}\n#{second_container}\n"
    )

    expect { verifier.verify }.to raise_error(Atlas::Deployment::CommandError) do |error|
      expect(error.message).to match(/exactly one running atlas container.*found 2/i)
      expect(error.message).not_to include(first_container)
      expect(error.message).not_to include(second_container)
      expect(error.message.bytesize).to be < 256
    end
    expect(runner).not_to have_received(:capture).with(array_including("inspect"))
  end

  it "rejects an empty immutable image identity" do
    allow(runner).to receive(:capture).with(
      [ "docker", "inspect", "--format", "{{.Image}}", "atlas-container" ]
    ).and_return("\n")

    expect { verifier.verify }.to raise_error(Atlas::Deployment::CommandError, /immutable image identity.*empty/i)
    expect(runner).not_to have_received(:capture).with(array_including("history"))
  end

  it "reports a running-container inspection failure without exposing container metadata" do
    container_id = "sensitive-container-identity"
    allow(runner).to receive(:capture).with(%w[docker compose ps -q atlas]).and_return("#{container_id}\n")
    allow(runner).to receive(:capture).with(
      [ "docker", "inspect", "--format", "{{.Image}}", container_id ]
    ).and_raise(
      Atlas::Deployment::CommandError,
      "command failed (1): docker inspect --format {{.Image}} #{container_id} — authorization=credential-value"
    )

    expect { verifier.verify }.to raise_error(Atlas::Deployment::CommandError) do |error|
      expect(error.message).to match(/could not inspect.*running atlas container image/i)
      expect(error.message).not_to include(container_id)
      expect(error.message).not_to include("credential-value")
      expect(error.message.bytesize).to be < 256
    end
  end

  it "rejects the configured secret in runtime image history without exposing it" do
    allow(runner).to receive(:capture).with(
      [ "docker", "history", "--no-trunc", "sha256:atlas-runtime" ]
    ).and_return("RUN configured-secret-value\n")
    verifier = described_class.new(
      runner:,
      repository_root:,
      env: { "RAILS_MASTER_KEY" => "configured-secret-value", "ATLAS_HOST" => "atlas.home.arpa" }
    )

    expect { verifier.verify }.to raise_error(Atlas::Deployment::CommandError) do |error|
      expect(error.message).to include("Docker image history contains sensitive material")
      expect(error.message).not_to include("configured-secret-value")
    end
  end

  it "rejects a recognized credential pattern in runtime image history without exposing it" do
    allow(runner).to receive(:capture).with(
      [ "docker", "history", "--no-trunc", "sha256:atlas-runtime" ]
    ).and_return("Authorization: Bearer history-credential-value\n")

    expect { verifier.verify }.to raise_error(Atlas::Deployment::CommandError) do |error|
      expect(error.message).to include("Docker image history contains sensitive material")
      expect(error.message).not_to include("history-credential-value")
    end
  end

  it "reports a runtime image-history failure without exposing image or credential metadata" do
    image_id = "sha256:sensitive-runtime-image"
    allow(runner).to receive(:capture).with(
      [ "docker", "inspect", "--format", "{{.Image}}", "atlas-container" ]
    ).and_return("#{image_id}\n")
    allow(runner).to receive(:capture).with(
      [ "docker", "history", "--no-trunc", image_id ]
    ).and_raise(
      Atlas::Deployment::CommandError,
      "command failed (1): docker history --no-trunc #{image_id} — authorization=credential-value"
    )

    expect { verifier.verify }.to raise_error(Atlas::Deployment::CommandError) do |error|
      expect(error.message).to match(/could not inspect.*runtime image history/i)
      expect(error.message).not_to include(image_id)
      expect(error.message).not_to include("credential-value")
      expect(error.message.bytesize).to be < 256
    end
    expect(runner).not_to have_received(:capture).with(
      [ "docker", "compose", "logs", "--no-color", "--tail", "1000", "atlas" ]
    )
  end

  it "scans logs after resolving runtime image history" do
    allow(runner).to receive(:capture).with(
      [ "docker", "compose", "logs", "--no-color", "--tail", "1000", "atlas" ]
    ).and_return("test-secret\n")

    expect { verifier.verify }.to raise_error(Atlas::Deployment::CommandError) do |error|
      expect(error.message).to include("container logs contain the Rails master key")
      expect(error.message).not_to include("test-secret")
    end
    expect(runner).to have_received(:capture).with(
      [ "docker", "history", "--no-trunc", "sha256:atlas-runtime" ]
    ).ordered
    expect(runner).to have_received(:capture).with(
      [ "docker", "compose", "logs", "--no-color", "--tail", "1000", "atlas" ]
    ).ordered
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
