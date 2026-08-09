require "rails_helper"

RSpec.describe "Local authentication", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:password) { "password123" }

  it "shows standard sign-in and sign-up pages" do
    get "/users/sign_in"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Log in")
    expect(response.body).to include("Remember me")

    get "/users/sign_up"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sign up")
    expect(response.body).to include("Preferred name")
  end

  it "creates one user and profile with a normalized email and secure password" do
    expect do
      post "/users",
           params: {
             user: {
               email: "  PILOT@EXAMPLE.COM ",
               password: password,
               password_confirmation: password,
               preferred_name: "Signal Pilot"
             }
           }
    end.to change(User, :count).by(1).and change(Profile, :count).by(1)

    user = User.last
    expect(user.email).to eq("pilot@example.com")
    expect(user.encrypted_password).to be_present
    expect(user.encrypted_password).not_to eq(password)
    expect(user.valid_password?(password)).to be(true)
    expect(user.profile.preferred_name).to eq("Signal Pilot")
    expect(user.profile.user).to eq(user)
    expect(response).to redirect_to("/")
  end

  it "rejects invalid signup without creating an orphan account" do
    expect do
      post "/users",
           params: {
             user: {
               email: "pilot@example.com",
               password: password,
               password_confirmation: "different",
               preferred_name: ""
             }
           }
    end.not_to change(User, :count)

    expect(Profile.count).to eq(0)
    expect(response).to have_http_status(:unprocessable_entity)
    page = Nokogiri::HTML(response.body)
    expect(page.text).to include("Password confirmation doesn't match Password")
    expect(page.text).to include("Preferred name can't be blank")
  end

  it "rejects malformed email and short passwords without persisting anything" do
    expect do
      post "/users",
           params: {
             user: {
               email: "not-an-email",
               password: "short",
               password_confirmation: "short",
               preferred_name: "Signal Pilot"
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
               password_confirmation: password,
               preferred_name: "Another Pilot"
             }
           }
    end.not_to change(User, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("has already been taken")
    expect(Profile.where(preferred_name: "Another Pilot")).to be_empty
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
