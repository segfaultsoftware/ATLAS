require "open3"
require "pathname"
require "tempfile"

RSpec.describe "the production runtime contract" do
  let(:repository_root) { Pathname.new(__dir__).join("../..").expand_path }
  let(:entrypoint) { repository_root.join("bin/docker-entrypoint").read }
  let(:dockerfile) { repository_root.join("Dockerfile").read }
  let(:production_environment) { repository_root.join("config/environments/production.rb").read }

  it "bootstraps the secret as root and drops application commands to UID/GID 1000" do
    expect(dockerfile).to include("apt-get install --no-install-recommends -y curl gosu")
    expect(dockerfile).to include("USER root")
    expect(entrypoint).to include("exec gosu 1000:1000")
    expect(entrypoint).to include("run_as_app_user")
  end

  it "prepares the database before starting the default Rails server" do
    server_guard = 'if [ "${@: -2:1}" == "./bin/rails" ] && [ "${@: -1:1}" == "server" ]; then'
    preparation = "./bin/rails db:prepare"
    server_start = 'run_as_app_user "$@"'

    expect(dockerfile).to include('ENTRYPOINT ["/rails/bin/docker-entrypoint"]')
    expect(dockerfile).to include('CMD ["./bin/thrust", "./bin/rails", "server"]')
    expect(entrypoint).to include(server_guard)
    expect(entrypoint).to include(preparation)
    expect(entrypoint.index(preparation)).to be < entrypoint.index(server_start)
  end

  it "bridges a configured secret file into Rails" do
    expect(entrypoint).to include('secret_path="${RAILS_MASTER_KEY_FILE:-/run/secrets/rails_master_key}"')

    Tempfile.create("atlas-master-key") do |secret|
      secret.write("test-key\n")
      secret.flush

      _stdout, stderr, status = Open3.capture3(
        { "RAILS_ENV" => "production", "RAILS_MASTER_KEY_FILE" => secret.path },
        repository_root.join("bin/docker-entrypoint").to_s,
        "ruby", "-e", 'abort unless ENV.fetch("RAILS_MASTER_KEY") == "test-key"'
      )

      expect(stderr).to eq("")
      expect(status).to be_success
    end
  end

  it "rejects missing production credentials" do
    _stdout, stderr, status = Open3.capture3(
      { "RAILS_ENV" => "production", "RAILS_MASTER_KEY" => nil, "RAILS_MASTER_KEY_FILE" => "/nonexistent/rails-master-key" },
      repository_root.join("bin/docker-entrypoint").to_s,
      "true"
    )

    expect(status).not_to be_success
    expect(stderr).to include("RAILS_MASTER_KEY is required in production")
  end

  if ENV["ATLAS_TEST_IMAGE"]
    it "bridges a real file-backed mount before dropping the application command" do
      Tempfile.create("atlas-mounted-master-key") do |secret|
        secret.write("test-key\n")
        secret.flush
        secret.chmod(0o600)

        _stdout, stderr, status = Open3.capture3(
          "docker", "run", "--rm", "--user", "0:0",
          "--mount", "type=bind,src=#{secret.path},dst=/run/secrets/rails_master_key,readonly",
          "-e", "RAILS_ENV=production", ENV.fetch("ATLAS_TEST_IMAGE"),
          "ruby", "-e", 'abort unless Process.uid == 1000 && ENV.fetch("RAILS_MASTER_KEY") == "test-key"'
        )

        expect(status).to be_success, stderr
      end
    end
  end

  it "configures Rails for the HTTPS reverse-proxy host" do
    expect(production_environment).to include("config.assume_ssl = true")
    expect(production_environment).to include("config.force_ssl = true")
    expect(production_environment).to include("config.ssl_options")
    expect(production_environment).to include('ENV.fetch("ATLAS_HOST", "atlas.home.arpa")')
    expect(production_environment).to include('protocol: "https"')
  end
end
