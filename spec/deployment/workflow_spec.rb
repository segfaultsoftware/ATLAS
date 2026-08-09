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
  let(:staging_job) { jobs.fetch("deploy_staging") }
  let(:deployment_jobs) { [ production_job, staging_job ] }

  it "triggers only for the trusted deployment refs" do
    expect(on_config.keys).to contain_exactly("push")
    expect(on_config.fetch("push").fetch("branches")).to contain_exactly("main")
    expect(on_config.fetch("push").fetch("tags")).to contain_exactly("prod")
  end

  it "defaults to read-only repository access and scopes staging write access to its job" do
    expect(workflow.fetch("permissions")).to eq("contents" => "read")
    expect(production_job.fetch("permissions")).to eq("contents" => "read")
    expect(staging_job.fetch("permissions")).to eq("contents" => "write")
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
    expect(staging_job.fetch("if")).to eq("github.ref == 'refs/heads/main'")
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

  it "passes deletion state and ephemeral Git authentication without copying it into application secrets" do
    deployment_jobs.each do |job|
      deployment = job.fetch("steps").find { |step| step.fetch("name") == "Run deployment automation" }
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
