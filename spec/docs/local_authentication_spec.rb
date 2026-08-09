require "rails_helper"

RSpec.describe "Local authentication rollout documentation" do
  it "describes local account administration" do
    readme = Rails.root.join("README.md").read

    expect(readme).to include("locally authenticated user")
    expect(readme).not_to include("existing Google-authenticated user")
  end

  it "documents the destructive reset and deployment implications" do
    deployment = Rails.root.join("docs/deployment.md").read

    expect(deployment).to include("destructive")
    expect(deployment).to include("no OAuth account migration")
    expect(deployment).to include("Profiles before Users")
    expect(deployment).to include("irreversible")
    expect(deployment).not_to include("Google OAuth is intentionally deferred")
  end
end
