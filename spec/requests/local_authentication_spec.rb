require "rails_helper"

RSpec.describe "Local authentication", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:password) { "password123" }

  it "renders the sign-in form with scoped structure and preserved semantics" do
    get "/users/sign_in"

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    panel = page.at_css("main.page-shell.auth-page > div.auth-page__panel")

    expect(panel).to be_present

    form = panel.at_css('form.auth-form[action="/users/sign_in"][method="post"]')

    expect(form).to be_present

    expect(panel.at_css("h1.auth-page__heading")&.text).to eq("Log in")
    expect(form.at_css('div.auth-form__field label[for="user_email"]')&.text).to eq("Email")
    expect(form.at_css('input.auth-form__input[name="user[email]"][type="email"][autofocus][autocomplete="email"]')).to be_present
    expect(form.at_css('div.auth-form__field label[for="user_password"]')&.text).to eq("Password")
    expect(form.at_css('input.auth-form__input[name="user[password]"][type="password"][autocomplete="current-password"]')).to be_present
    expect(form.at_css('div.auth-form__remember input.auth-form__checkbox[name="user[remember_me]"][type="checkbox"]')).to be_present
    expect(form.at_css('div.auth-form__remember label[for="user_remember_me"]')&.text).to eq("Remember me")
    expect(form.at_css('input.auth-form__submit[type="submit"][value="Log in"]')).to be_present
    expect(panel.at_css('p.auth-page__alternate a.auth-page__link[href="/users/sign_up"]')&.text).to eq("Sign up")
  end

  it "renders the sign-up form with scoped structure and preserved semantics" do
    get "/users/sign_up"

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    panel = page.at_css("main.page-shell.auth-page > div.auth-page__panel")

    expect(panel).to be_present

    form = panel.at_css('form.auth-form[action="/users"][method="post"]')

    expect(form).to be_present

    expect(panel.at_css("h1.auth-page__heading")&.text).to eq("Sign up")
    expect(form.at_css('div.auth-form__field label[for="user_email"]')&.text).to eq("Email")
    expect(form.at_css('input.auth-form__input[name="user[email]"][type="email"][autofocus][autocomplete="email"]')).to be_present
    expect(form.at_css('div.auth-form__field label[for="user_password"]')&.text).to eq("Password")
    expect(form.at_css('input.auth-form__input[name="user[password]"][type="password"][autocomplete="new-password"]')).to be_present
    expect(form.at_css("small.auth-form__hint")&.text).to include("characters minimum")
    expect(form.at_css('div.auth-form__field label[for="user_password_confirmation"]')&.text).to eq("Password confirmation")
    expect(form.at_css('input.auth-form__input[name="user[password_confirmation]"][type="password"][autocomplete="new-password"]')).to be_present
    expect(form.css("input.auth-form__input").map { |input| input["name"] }).to contain_exactly(
      "user[email]",
      "user[password]",
      "user[password_confirmation]"
    )
    expect(form.at_css('input.auth-form__submit[type="submit"][value="Sign up"]')).to be_present
    expect(panel.at_css('p.auth-page__alternate a.auth-page__link[href="/users/sign_in"]')&.text).to eq("Log in")
  end

  it "creates one user and profile while ignoring the retired profile name input" do
    retired_profile_name_key = [ "preferred", "name" ].join("_")

    expect do
      post "/users",
           params: {
             user: {
               email: "  PILOT@EXAMPLE.COM ",
               password: password,
               password_confirmation: password,
               retired_profile_name_key => "ignored"
             }
           }
    end.to change(User, :count).by(1).and change(Profile, :count).by(1)

    user = User.last
    expect(user.email).to eq("pilot@example.com")
    expect(user.encrypted_password).to be_present
    expect(user.encrypted_password).not_to eq(password)
    expect(user.valid_password?(password)).to be(true)
    expect(user.profile.user).to eq(user)
    expect(response).to redirect_to("/")
  end

  it "rejects signup without password confirmation" do
    expect do
      post "/users",
           params: {
             user: {
               email: "pilot@example.com",
               password: password
             }
           }
    end.not_to change(User, :count)

    expect(Profile.count).to eq(0)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Nokogiri::HTML(response.body).text).to include("Password confirmation can't be blank")
  end

  it "rejects invalid signup without creating an orphan account" do
    expect do
      post "/users",
           params: {
             user: {
               email: "pilot@example.com",
               password: password,
               password_confirmation: "different"
             }
           }
    end.not_to change(User, :count)

    expect(Profile.count).to eq(0)
    expect(response).to have_http_status(:unprocessable_entity)
    page = Nokogiri::HTML(response.body)
    errors = page.at_css('div#error_explanation.auth-errors[role="alert"]')

    expect(errors).to be_present

    expect(errors.at_css("h2.auth-errors__heading")&.text).to include("prevented this account from being saved")
    messages = errors.css("ul.auth-errors__list > li").map { |item| item.text.strip }
    expect(messages).to include("Password confirmation doesn't match Password")
  end

  it "rejects malformed email and short passwords without persisting anything" do
    expect do
      post "/users",
           params: {
             user: {
               email: "not-an-email",
               password: "short",
               password_confirmation: "short"
             }
           }
    end.not_to change(User, :count)

    expect(Profile.count).to eq(0)
    expect(response).to have_http_status(:unprocessable_entity)
    page = Nokogiri::HTML(response.body)
    expect(page.text).to include("Email is invalid")
    expect(page.text).to include("Password is too short")
  end

  it "rejects case-variant duplicate email addresses" do
    FactoryBot.create(:user, email: "pilot@example.com")

    expect do
      post "/users",
           params: {
             user: {
               email: "PILOT@EXAMPLE.COM",
               password: password,
               password_confirmation: password
             }
           }
    end.not_to change(User, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("has already been taken")
    expect(Profile.count).to eq(0)
  end

  it "logs in with remember-me and logs out" do
    user = FactoryBot.create(:user, email: "pilot@example.com", password: password, password_confirmation: password)

    post "/users/sign_in",
         params: {
           user: {
             email: user.email,
             password: password,
             remember_me: "1"
           }
         }

    expect(response).to redirect_to("/")
    expect(response.cookies["remember_user_token"]).to be_present

    delete "/logout"

    expect(response).to redirect_to("/")
    expect(response.cookies["remember_user_token"]).to be_blank
  end

  it "does not authenticate with an incorrect password" do
    user = FactoryBot.create(:user, email: "pilot@example.com", password: password, password_confirmation: password)

    post "/users/sign_in",
         params: {
           user: {
             email: user.email,
             password: "incorrect-password"
           }
         }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.cookies["remember_user_token"]).to be_blank

    get "/profile"

    expect(response).to redirect_to("/")
  end
end
