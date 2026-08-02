require "rails_helper"

RSpec.describe "Webadmin Manual pages", type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:manual_page) do
    FactoryBot.create(
      :manual_page,
      title: "Combat",
      slug: "combat",
      content: "# Combat\n\nResolve actions in order."
    )
  end
  let!(:webadmin) { FactoryBot.create(:user, role: :webadmin) }
  let!(:user) { FactoryBot.create(:user) }

  it "requires authentication for the editor" do
    get "/webadmin/manual_pages/new"

    expect(response).to redirect_to("/")
  end

  it "denies editor access to ordinary Users" do
    sign_in user

    get "/webadmin/manual_pages/new"

    expect(response).to redirect_to("/")
  end

  it "provides a native Markdown editor for Webadmins" do
    sign_in webadmin

    get "/webadmin/manual_pages/#{manual_page.id}/edit"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("manual_page_content")
    expect(response.body).to include("Preview")
  end

  it "creates live Manual pages" do
    sign_in webadmin

    expect {
      post "/webadmin/manual_pages", params: {
        manual_page: {
          title: "Getting Started",
          slug: "getting-started",
          content: "# Getting Started"
        }
      }
    }.to change(ManualPage, :count).by(1)

    created_page = ManualPage.order(:created_at, :id).last
    expect(created_page).to have_attributes(
      title: "Getting Started",
      slug: "getting-started",
      content: "# Getting Started"
    )
    expect(response).to redirect_to("/webadmin/manual_pages/#{created_page.id}/edit")
  end

  it "makes saved edits live immediately" do
    sign_in webadmin

    patch "/webadmin/manual_pages/#{manual_page.id}", params: {
      manual_page: { content: "# Updated Combat" }
    }

    expect(response).to redirect_to("/webadmin/manual_pages/#{manual_page.id}/edit")
    expect(manual_page.reload.content).to eq("# Updated Combat")

    get "/manual/combat"

    expect(response.body).to include("Updated Combat")
  end

  it "previews unsaved Markdown with the public sanitization boundary" do
    sign_in webadmin

    post "/webadmin/manual_pages/preview", params: {
      manual_page: {
        title: "Preview",
        slug: "preview",
        content: "# Preview\n\n<img src=\"x\" onerror=\"alert(1)\">"
      }
    }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="preview"')
    expect(response.body).not_to include("onerror")
  end
end
