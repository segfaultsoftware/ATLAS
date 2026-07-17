require "rails_helper"

RSpec.describe "SRD", type: :request do
  it "renders the public SRD from the Markdown source" do
    get "/srd"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ATLAS SRD")
    expect(response.body).to include("Core Ideas")
    expect(response.body).to include("science-fiction tabletop roleplaying game")
  end

  it "renders the public SRD with a trailing slash" do
    get "/srd/"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ATLAS SRD")
  end
end
