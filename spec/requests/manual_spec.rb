require "rails_helper"

RSpec.describe "Manual", type: :request do
  let!(:landing_page) do
    FactoryBot.create(
      :manual_page,
      title: "Manual Home",
      slug: "index",
      content: <<~MARKDOWN
        # Manual Home

        Welcome to the Manual.

        ## Getting Started

        Begin here.
      MARKDOWN
    )
  end
  let!(:parent_page) do
    FactoryBot.create(
      :manual_page,
      title: "Rules",
      slug: "rules",
      content: "# Rules"
    )
  end
  let!(:manual_page) do
    FactoryBot.create(
      :manual_page,
      title: "Combat",
      slug: "combat",
      parent: parent_page,
      content: <<~MARKDOWN
        # Combat

        ## Turns

        Resolve actions in order.
      MARKDOWN
    )
  end
  let!(:next_page) do
    FactoryBot.create(
      :manual_page,
      title: "Equipment",
      slug: "equipment",
      parent: parent_page,
      content: "# Equipment"
    )
  end
  let!(:category) { FactoryBot.create(:manual_category, name: "Core Rules", slug: "core-rules") }

  before do
    manual_page.categories << category
  end

  it "redirects the Manual root to the configured landing page" do
    get "/manual"

    expect(response).to redirect_to("/manual/index")
  end

  it "renders a database-backed page through the Markdown pipeline" do
    get "/manual/combat"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Combat")
    expect(response.body).to include("Resolve actions in order.")
    expect(response.body).to include('id="turns"')
  end

  it "renders wiki navigation for the page" do
    get "/manual/combat"

    expect(response.body).to include('aria-label="Breadcrumb"')
    expect(response.body).to include("Rules")
    expect(response.body).to include("Core Rules")
    expect(response.body).to include('aria-label="Table of contents"')
    expect(response.body).to include('href="#turns"')
    expect(response.body).to include("Next: Equipment")
    expect(response.body).to include("Latest updates")
  end

  it "allows public reading without an authenticated user" do
    get "/manual/combat"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Edit")
  end

  it "links the landing page and stable page URLs by slug" do
    expect(landing_page.to_param).to eq("index")
    expect(manual_page.to_param).to eq("combat")

    get "/manual/index"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Manual Home")
  end

  it "limits latest updates to the five most recently updated pages" do
    6.times do |number|
      FactoryBot.create(:manual_page, title: "Recent #{number}", slug: "recent-#{number}")
    end

    get "/manual/combat"

    expect(response.body).to include("Recent 5")
    expect(response.body).not_to include("Recent 0")
  end
end
