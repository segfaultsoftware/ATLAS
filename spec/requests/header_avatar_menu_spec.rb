require "rails_helper"

RSpec.describe "Header avatar menu", type: :request do
  include Devise::Test::IntegrationHelpers

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
    account_menu = page.at_css(".account-menu")
    menu_button = account_menu.at_css("button.account-menu__button")
    menu = account_menu.at_css('[role="menu"]')

    expect(account_menu["data-controller"]).to eq("account-menu")
    expect(account_menu["data-action"]).to include("keydown.esc->account-menu#close")
    expect(account_menu["data-action"]).to include("focusout->account-menu#closeWhenFocusLeaves")
    expect(menu_button["aria-expanded"]).to eq("false")
    expect(menu_button["aria-haspopup"]).to eq("menu")
    expect(menu_button["data-action"]).to eq("click->account-menu#toggle")
    expect(menu_button.text).to include("😢")
    expect(menu.attribute("hidden")).to be_present
    expect(menu.at_css('a[href="/profile"][role="menuitem"]').text).to include("View/edit profile")
    expect(menu.at_css('form[action="/logout"] input[name="_method"][value="delete"]')).to be_present
    expect(menu.at_css('button[role="menuitem"]').text).to include("Log out")
  end

  it "renders the default avatar when the authenticated user has no profile avatar" do
    user = FactoryBot.create(:user)
    sign_in user

    get "/"

    expect(response).to have_http_status(:ok)
    menu_button = Nokogiri::HTML(response.body).at_css("button.account-menu__button")
    expect(menu_button.text).to include("🙂")
  end
end
