require "yaml"
require "pathname"

RSpec.describe "the production Compose contract" do
  let(:repository_root) { Pathname.new(__dir__).join("../..").expand_path }
  let(:compose) { YAML.load_file(repository_root.join("compose.yaml"), aliases: true) }
  let(:service) { compose.fetch("services").fetch("atlas") }

  it "builds the checked-out repository on the shared and private networks" do
    expect(service.fetch("build").fetch("context")).to eq(".")
    expect(service.fetch("networks")).to contain_exactly("web", "internal")
    expect(compose.dig("networks", "web", "external")).to be(true)
    expect(compose.dig("networks", "internal", "internal")).to be(true)
  end

  it "keeps the service private to Docker networks and persists primary storage" do
    expect(service["ports"]).to be_nil.or(be_empty)
    expect(service.fetch("expose")).to include("80")
    expect(service.fetch("volumes")).to include("./storage:/rails/storage")
  end

  it "mounts the Rails master key read-only and checks the health endpoint" do
    secret = service.fetch("secrets").fetch(0)
    expect(secret).to include(
      "source" => "rails_master_key",
      "target" => "rails_master_key",
      "uid" => "1000",
      "gid" => "1000"
    )
    expect(secret.fetch("mode").to_i).to eq(0o400)
    expect(compose.dig("secrets", "rails_master_key", "file")).to include("RAILS_MASTER_KEY_FILE")
    expect(service.fetch("environment")).not_to have_key("RAILS_MASTER_KEY")

    healthcheck = service.dig("healthcheck", "test").join(" ")
    expect(healthcheck).to include("/up", "Host:", "ATLAS_HOST")
  end

  it "does not add cache, queue, cable, or Redis services" do
    expect(compose.fetch("services").keys).to contain_exactly("atlas")
  end
end
