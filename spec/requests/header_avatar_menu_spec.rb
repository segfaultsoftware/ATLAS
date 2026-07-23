require "rails_helper"

RSpec.describe "Header avatar menu", type: :request do
  include Devise::Test::IntegrationHelpers

  def profile_selects_during
    queries = []
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      queries << payload[:sql] if payload[:sql].match?(/\bFROM "profiles"\b/)
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      yield
    end

    queries
  end

  def application_css
    Rails.root.join("app/assets/stylesheets/application.css").read
  end

  it "renders a shared public header with home branding and one auth control" do
    [ "/", "/srd", "/srd/", "/status" ].each do |path|
      get path

      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      header = page.at_css("body > header.site-header")
      brand = header.at_css('a.site-brand[href="/"]')
      auth_forms = header.css('form[action="/users/auth/google_oauth2"]')

      expect(brand.at_css('.site-brand__mark[aria-hidden="true"]')).to be_present
      expect(brand.at_css(".pixel-spaceship")).to be_present
      expect(brand.at_css(".site-brand__text").text).to eq("ATLAS")
      expect(auth_forms.size).to eq(1)
      expect(auth_forms.css("button").map(&:text).map(&:strip)).to contain_exactly("Login/Register")
      expect(page.at_css(".account-menu")).to be_nil
    end
  end

  it "keeps the public header in normal page flow" do
    site_navigation_css = application_css[/\.site-navigation \{[^}]+\}/]

    expect(site_navigation_css).to include("display: flex;")
    expect(site_navigation_css).not_to include("position: fixed")
  end

  it "renders the current profile avatar without account menu actions" do
    user = FactoryBot.create(:user)
    FactoryBot.create(:profile, user: user, avatar_key: "cry")
    sign_in user

    get "/"

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    avatar = page.at_css(".header-avatar")

    expect(avatar.text).to include("😢")
    expect(page.at_css(".account-menu")).to be_nil
    expect(page.at_css('[role="menu"]')).to be_nil
    expect(page.at_css('[role="menuitem"]')).to be_nil
    expect(page.at_css('a[href="/profile"]')).to be_nil
    expect(page.at_css('form[action="/logout"]')).to be_nil
    expect(page.text).not_to include("View/edit profile")
    expect(page.text).not_to include("Log out")
  end

  it "renders the default avatar when the authenticated user has no profile avatar" do
    user = FactoryBot.create(:user)
    sign_in user

    get "/"

    expect(response).to have_http_status(:ok)
    avatar = Nokogiri::HTML(response.body).at_css(".header-avatar")
    expect(avatar.text).to include("🙂")
  end

  it "uses the cached header avatar on later authenticated requests" do
    user = FactoryBot.create(:user)
    FactoryBot.create(:profile, user: user, avatar_key: "cry")
    sign_in user

    get "/"
    expect(Nokogiri::HTML(response.body).at_css(".header-avatar").text).to include("😢")

    expect_any_instance_of(User).not_to receive(:profile)

    profile_queries = profile_selects_during do
      get "/srd"
    end

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css(".header-avatar").text).to include("😢")
    expect(profile_queries).to be_empty
  end

  it "refreshes the header avatar after saving profile changes" do
    user = FactoryBot.create(:user)
    FactoryBot.create(:profile, user: user, avatar_key: "cry")
    sign_in user

    get "/"
    expect(Nokogiri::HTML(response.body).at_css(".header-avatar").text).to include("😢")

    patch "/profile",
          params: {
            profile: {
              preferred_name: "Signal Pilot",
              pronouns: "they/them",
              preferred_playtimes: "Weeknights",
              avatar_key: "frown"
            }
          }
    follow_redirect!

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css(".header-avatar").text).to include("🙁")
  end
end
