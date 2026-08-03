require "open3"
require "pathname"
require "tempfile"

RSpec.describe "the production runtime contract" do
  let(:repository_root) { Pathname.new(__dir__).join("../..").expand_path }
  let(:entrypoint) { repository_root.join("bin/docker-entrypoint").read }
  let(:production_environment) { repository_root.join("config/environments/production.rb").read }

  it "bridges a mounted Compose secret into Rails" do
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

  it "configures Rails for the HTTPS reverse-proxy host" do
    expect(production_environment).to include("config.assume_ssl = true")
    expect(production_environment).to include("config.force_ssl = true")
    expect(production_environment).to include("config.ssl_options")
    expect(production_environment).to include('ENV.fetch("ATLAS_HOST", "atlas.home.arpa")')
    expect(production_environment).to include('protocol: "https"')
  end
end
