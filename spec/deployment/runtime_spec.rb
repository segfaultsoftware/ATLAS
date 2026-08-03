require "pathname"

RSpec.describe "the production runtime contract" do
  let(:repository_root) { Pathname.new(__dir__).join("../..").expand_path }
  let(:entrypoint) { repository_root.join("bin/docker-entrypoint").read }
  let(:production_environment) { repository_root.join("config/environments/production.rb").read }

  it "bridges the Compose secret and rejects missing production credentials" do
    expect(entrypoint).to include("/run/secrets/rails_master_key")
    expect(entrypoint).to include("RAILS_MASTER_KEY")
    expect(entrypoint).to include("RAILS_MASTER_KEY is required")
  end

  it "configures Rails for the HTTPS reverse-proxy host" do
    expect(production_environment).to include("config.assume_ssl = true")
    expect(production_environment).to include("config.force_ssl = true")
    expect(production_environment).to include("config.ssl_options")
    expect(production_environment).to include('ENV.fetch("ATLAS_HOST", "atlas.home.arpa")')
    expect(production_environment).to include('protocol: "https"')
  end
end
