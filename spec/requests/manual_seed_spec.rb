require "rails_helper"

RSpec.describe "Manual seed migration", type: :request do
  it "imports the existing SRD into the database-backed landing page" do
    2.times { load Rails.root.join("db/seeds.rb") }

    page = ManualPage.find_by!(slug: "index")

    expect(page).to have_attributes(title: "ATLAS SRD", slug: "index")
    expect(page.content).to eq(File.binread(Rails.root.join("docs/srd/atlas-srd.md")))
    expect(ManualPage.where(slug: "index").count).to eq(1)

    get "/manual/index"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ATLAS SRD")
  end
end
