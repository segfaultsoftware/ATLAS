require "rails_helper"

RSpec.describe "Google authentication", type: :request do
  def google_auth_hash(uid: "google-123", email: "player@example.com", name: "Atlas Player")
    OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: {
        email: email,
        name: name
      }
    )
  end

  def mock_google_auth(auth_hash = google_auth_hash)
    OmniAuth.config.mock_auth[:google_oauth2] = auth_hash
  end

  def complete_google_login
    post "/users/auth/google_oauth2"
    follow_redirect!
  end

  around do |example|
    previous_test_mode = OmniAuth.config.test_mode
    previous_mock_auth = OmniAuth.config.mock_auth[:google_oauth2]

    OmniAuth.config.test_mode = true
    mock_google_auth
    example.run
  ensure
    OmniAuth.config.mock_auth[:google_oauth2] = previous_mock_auth
    OmniAuth.config.test_mode = previous_test_mode
  end

  it "offers a public Login/Register control that starts Google OAuth only" do
    get "/"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Login/Register")
    expect(response.body).to include('action="/users/auth/google_oauth2"')
    expect(response.body).not_to include("/users/sign_in")
    expect(response.body).not_to include("/users/sign_up")
  end

  it "creates a Google auth identity and remembers the signed-in session" do
    expect do
      complete_google_login
    end.to change(User, :count).by(1)

    user = User.last
    expect(user.provider).to eq("google_oauth2")
    expect(user.uid).to eq("google-123")
    expect(user.email).to eq("player@example.com")
    expect(user.name).to eq("Atlas Player")
    expect(user.remember_created_at).to be_present
    expect(response.cookies["remember_user_token"]).to be_present

    expect(response).to redirect_to("/")
    follow_redirect!

    get "/"
    expect(response.body).to include("Log out")
    expect(response.body).not_to include("Login/Register")
  end

  it "reuses an existing Google auth identity on callback" do
    User.create!(
      provider: "google_oauth2",
      uid: "google-123",
      email: "old@example.com",
      name: "Old Name"
    )

    expect do
      complete_google_login
    end.not_to change(User, :count)

    user = User.last
    expect(user.email).to eq("player@example.com")
    expect(user.name).to eq("Atlas Player")
  end

  it "redirects to the stored destination after callback" do
    allow_any_instance_of(Users::OmniauthCallbacksController)
      .to receive(:stored_location_for)
      .with(:user)
      .and_return("/srd")

    get "/users/auth/google_oauth2/callback",
        env: {
          "omniauth.auth" => google_auth_hash
        }

    expect(response).to redirect_to("/srd")
  end

  it "logs out and clears the authenticated session" do
    complete_google_login
    follow_redirect!

    delete "/logout"

    expect(response).to redirect_to("/")
    follow_redirect!
    expect(response.body).to include("Login/Register")
    expect(response.body).not_to include("Log out")
  end
end
