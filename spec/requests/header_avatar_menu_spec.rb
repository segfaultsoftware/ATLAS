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

  it "keeps public pages on the Login/Register entry point without rendering an account menu" do
    get "/"

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css('form[action="/users/auth/google_oauth2"]')).to be_present
    expect(page.at_css(".account-menu")).to be_nil
  end

  it "renders the current profile avatar with profile and logout menu actions" do
    user = FactoryBot.create(:user)
    FactoryBot.create(:profile, user: user, avatar_key: "cry")
    sign_in user

    get "/"

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    account_menu = page.at_css("details.account-menu")
    menu_button = account_menu.at_css("summary.account-menu__button")
    menu = account_menu.at_css('[role="menu"]')

    expect(account_menu["data-controller"]).to eq("account-menu")
    expect(account_menu["data-action"]).to include("keydown.esc->account-menu#close")
    expect(account_menu["data-action"]).to include("focusout->account-menu#closeWhenFocusLeaves")
    expect(account_menu["data-action"]).to include("toggle->account-menu#syncExpanded")
    expect(menu_button["aria-expanded"]).to eq("false")
    expect(menu_button["aria-haspopup"]).to eq("menu")
    expect(menu_button.text).to include("😢")
    expect(menu.attribute("hidden")).to be_nil
    expect(menu.at_css('a[href="/profile"][role="menuitem"]').text).to include("View/edit profile")
    expect(menu.at_css('form[action="/logout"] input[name="_method"][value="delete"]')).to be_present
    expect(menu.at_css('button[role="menuitem"]').text).to include("Log out")
  end

  it "keeps the native details fallback menu hidden until opened" do
    expect(application_css).to include(".account-menu:not([open]) .account-menu__menu")
    expect(application_css).to include("display: none;")
  end

  it "renders the default avatar when the authenticated user has no profile avatar" do
    user = FactoryBot.create(:user)
    sign_in user

    get "/"

    expect(response).to have_http_status(:ok)
    menu_button = Nokogiri::HTML(response.body).at_css("summary.account-menu__button")
    expect(menu_button.text).to include("🙂")
  end

  it "uses the cached header avatar on later authenticated requests" do
    user = FactoryBot.create(:user)
    FactoryBot.create(:profile, user: user, avatar_key: "cry")
    sign_in user

    get "/"
    expect(Nokogiri::HTML(response.body).at_css("summary.account-menu__button").text).to include("😢")

    expect_any_instance_of(User).not_to receive(:profile)

    profile_queries = profile_selects_during do
      get "/srd"
    end

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css("summary.account-menu__button").text).to include("😢")
    expect(profile_queries).to be_empty
  end

  it "refreshes the header avatar after saving profile changes" do
    user = FactoryBot.create(:user)
    FactoryBot.create(:profile, user: user, avatar_key: "cry")
    sign_in user

    get "/"
    expect(Nokogiri::HTML(response.body).at_css("summary.account-menu__button").text).to include("😢")

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
    expect(Nokogiri::HTML(response.body).at_css("summary.account-menu__button").text).to include("🙁")
  end
end
