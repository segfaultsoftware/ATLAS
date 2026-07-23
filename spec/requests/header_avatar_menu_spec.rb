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

  def account_menu_controller
    Rails.root.join("app/javascript/controllers/account_menu_controller.js").read
  end

  it "renders the current profile avatar as an account menu trigger" do
    user = FactoryBot.create(:user)
    FactoryBot.create(:profile, user: user, avatar_key: "cry")
    sign_in user

    get "/"

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    menu = page.at_css("details.account-menu")
    trigger = menu.at_css("summary.account-menu__button")
    avatar = trigger.at_css(".header-avatar")
    menu_panel = menu.at_css('.account-menu__menu[role="menu"]')
    profile_link = menu_panel.at_css('a.account-menu__item[role="menuitem"][href="/profile"]')
    logout_form = menu_panel.at_css('form.account-menu__form[action="/logout"][method="post"]')
    logout_button = logout_form.at_css('button.account-menu__item[role="menuitem"]')

    expect(menu["data-controller"]).to eq("account-menu")
    expect(trigger["aria-label"]).to eq("Account menu")
    expect(trigger["aria-haspopup"]).to eq("menu")
    expect(trigger["aria-expanded"]).to eq("false")
    expect(trigger["data-account-menu-target"]).to eq("summary")
    expect(avatar.text).to include("😢")
    expect(menu_panel.css('[role="menuitem"]').map(&:text).map(&:strip)).to contain_exactly("Profile", "Logout")
    expect(profile_link.text.strip).to eq("Profile")
    expect(logout_form.at_css('input[name="_method"][value="delete"]')).to be_present
    expect(logout_button.text.strip).to eq("Logout")
    expect(page.text).not_to include("Login/Register")
  end

  it "wires the account menu for native details fallback and controller behavior" do
    user = FactoryBot.create(:user)
    sign_in user

    get "/"

    page = Nokogiri::HTML(response.body)
    menu = page.at_css("details.account-menu")
    account_menu_css = application_css

    expect(menu["data-action"]).to include("keydown.esc->account-menu#close")
    expect(menu["data-action"]).to include("focusout->account-menu#closeWhenFocusLeaves")
    expect(menu["data-action"]).to include("toggle->account-menu#syncExpanded")
    expect(account_menu_css).to include(".account-menu:not([open]) .account-menu__menu")
    expect(account_menu_css).to include(".account-menu__button::-webkit-details-marker")
    expect(account_menu_controller).to include("closeWhenFocusLeaves")
    expect(account_menu_controller).to include("syncExpanded")
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
