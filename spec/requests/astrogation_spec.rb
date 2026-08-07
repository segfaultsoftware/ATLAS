require "rails_helper"

RSpec.describe "Astrogation", type: :request do
  it "renders the public scene with the shared header and all entities" do
    get "/astrogation"

    expect(response).to have_http_status(:ok)

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("body > header.site-header")).to be_present
    expect(page.css("[data-astrogation-entity]").map { |entity| entity["data-name"] }).to eq(
      [ "Tejat A", "Tejat B", "Tejat C", "Ketrak Station", "Gate Alpha", "Gate Beta", "Ship" ]
    )
    expect(page.at_css("#astrogation-system")["data-astrogation-units"]).to eq("million-kilometres")
    expect(page.css("[data-astrogation-entity]").map { |entity| [ entity["data-name"], entity["data-x"], entity["data-y"] ] }).to eq(
      [
        [ "Tejat A", "140.0", "0.0" ],
        [ "Tejat B", "553.892", "534.887" ],
        [ "Tejat C", "-24.433", "1399.787" ],
        [ "Ketrak Station", "-1285.575", "-1532.089" ],
        [ "Gate Alpha", "2500.0", "0.0" ],
        [ "Gate Beta", "-2500.0", "0.0" ],
        [ "Ship", "-402.776", "520.224" ]
      ]
    )
  end

  it "renders the same server contract on repeated requests" do
    get "/astrogation"
    first_body = response.body

    get "/astrogation"

    expect(response.body).to eq(first_body)
  end

  it "does not persist system state" do
    expect { get "/astrogation" }.not_to change { [ User.count, Profile.count ] }
  end
end
