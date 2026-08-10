require "yaml"

RSpec.describe "deployment workflow contract" do
  def workflow_file(name)
    YAML.safe_load(File.read(File.expand_path("../../.github/workflows/#{name}.yml", __dir__)), aliases: true)
  end

  let(:workflow) { workflow_file("deploy") }
  let(:ci_workflow) { workflow_file("ci") }
  let(:on_config) { workflow["on"] || workflow.fetch(true) }
  let(:ci_on_config) { ci_workflow["on"] || ci_workflow.fetch(true) }
  let(:jobs) { workflow.fetch("jobs") }
  let(:production_job) { jobs.fetch("deploy_production") }
  let(:staging_main_job) { jobs.fetch("deploy_staging_from_main") }
  let(:staging_tag_job) { jobs.fetch("deploy_staging_from_tag") }
  let(:deployment_jobs) { [ production_job, staging_main_job, staging_tag_job ] }

  it "triggers only for the trusted deployment refs" do
    expect(on_config.keys).to contain_exactly("push")
    expect(on_config.fetch("push").fetch("branches")).to contain_exactly("main")
    expect(on_config.fetch("push").fetch("tags")).to contain_exactly("prod", "staging")
  end

  it "keeps built-in workflow tokens read-only" do
    expect(workflow.fetch("permissions")).to eq("contents" => "read")
    expect(production_job.fetch("permissions")).to eq("contents" => "read")
    expect(staging_main_job.fetch("permissions")).to eq("contents" => "read")
    expect(staging_tag_job.fetch("permissions")).to eq("contents" => "read")
  end

  it "serializes deployment mutations on the dedicated runner" do
    expect(deployment_jobs).to all(satisfy do |job|
      expect(job.fetch("runs-on")).to eq(
        "group" => "atlas-deployment",
        "labels" => [ "self-hosted", "atlas-deployment" ]
      )
      expect(job.fetch("concurrency")).to eq(
        "group" => "atlas-deployment-${{ github.repository }}",
        "cancel-in-progress" => false
      )
    end)
  end

  it "routes each trusted ref to its permission-scoped job" do
    expect(production_job.fetch("if")).to eq("github.ref == 'refs/tags/prod'")
    expect(staging_main_job.fetch("if")).to eq("github.ref == 'refs/heads/main'")
    expect(staging_tag_job.fetch("if")).to eq(
      "github.ref == 'refs/tags/staging' && github.actor != 'atlas-staging-tag-automation[bot]'"
    )
  end

  it "does not persist checkout credentials and invokes the tested entry point" do
    deployment_jobs.each do |job|
      steps = job.fetch("steps")
      checkout = steps.find { |step| step.fetch("uses", "").start_with?("actions/checkout@") }
      ruby_setup = steps.find { |step| step.fetch("uses", "").start_with?("ruby/setup-ruby@") }
      deployment = steps.find { |step| step.fetch("name") == "Run deployment automation" }

      expect(checkout.fetch("uses")).to match(/\Aactions\/checkout@[0-9a-f]{40}\z/)
      expect(checkout.dig("with", "persist-credentials")).to be(false)
      expect(ruby_setup.fetch("uses")).to match(/\Aruby\/setup-ruby@[0-9a-f]{40}\z/)
      expect(ruby_setup.dig("with", "bundler-cache")).to be(true)
      expect(deployment.fetch("run")).to include("bin/deployment-automation")
    end
  end

  it "uses the built-in token only for production's read-only deployment" do
    deployment = production_job.fetch("steps").find { |step| step.fetch("name") == "Run deployment automation" }
    environment = deployment.fetch("env")

    expect(environment).to include(
      "GITHUB_BEFORE" => "${{ github.event.before }}",
      "GITHUB_REF_DELETED" => "${{ github.event.deleted }}",
      "GIT_CONFIG_COUNT" => "1",
      "GIT_CONFIG_KEY_0" => "http.https://github.com/.extraheader"
    )
    expect(environment.fetch("GIT_CONFIG_VALUE_0")).to include("${{ github.token }}")
    expect(deployment.fetch("run")).not_to include("echo", "secrets.")
  end

  it "mints a dedicated GitHub App token only for main-driven staging-tag updates" do
    token_step = staging_main_job.fetch("steps").find { |step| step["id"] == "staging_tag_token" }
    deployment = staging_main_job.fetch("steps").find { |step| step.fetch("name") == "Run deployment automation" }
    environment = deployment.fetch("env")

    expect(staging_main_job.fetch("environment")).to eq("staging-tag-automation")
    expect(token_step.fetch("uses")).to eq("actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1")
    expect(token_step.fetch("with")).to eq(
      "client-id" => "${{ vars.STAGING_TAG_APP_CLIENT_ID }}",
      "private-key" => "${{ secrets.STAGING_TAG_APP_PRIVATE_KEY }}",
      "permission-contents" => "write"
    )
    expect(environment.fetch("GIT_CONFIG_VALUE_0")).to eq("AUTHORIZATION: bearer ${{ steps.staging_tag_token.outputs.token }}")
    expect(deployment.fetch("run")).not_to include("echo", "secrets.")
  end

  it "uses only the read-only built-in token for operator-driven staging-tag deployments" do
    token_step = staging_tag_job.fetch("steps").find { |step| step["id"] == "staging_tag_token" }
    deployment = staging_tag_job.fetch("steps").find { |step| step.fetch("name") == "Run deployment automation" }
    environment = deployment.fetch("env")

    expect(staging_tag_job).not_to have_key("environment")
    expect(token_step).to be_nil
    expect(environment.fetch("GIT_CONFIG_VALUE_0")).to eq("AUTHORIZATION: bearer ${{ github.token }}")
    expect(deployment.fetch("run")).not_to include("echo", "secrets.")
  end

  it "keeps public CI on hosted runners with its pull-request boundary" do
    expect(ci_on_config).to have_key("pull_request")
    expect(ci_workflow.fetch("jobs").values).to all(satisfy { |ci_job| ci_job.fetch("runs-on") == "ubuntu-latest" })
    expect(ci_workflow.to_s).not_to include("atlas-deployment", "self-hosted")
  end

  it "clears Git authentication before loading repository deployment code" do
    entrypoint = File.read(File.expand_path("../../bin/deployment-automation", __dir__))

    expect(entrypoint.index('ENV.delete("GIT_CONFIG_VALUE_0")')).to be < entrypoint.index('require_relative "../lib/atlas/deployment_automation"')
  end
end
