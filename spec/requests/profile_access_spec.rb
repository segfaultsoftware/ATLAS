require "rails_helper"

RSpec.describe "Profile access", type: :request do
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

  it "blocks anonymous profile access and stores the intended destination for login" do
    get "/profile"

    expect(response).to redirect_to("/")
    follow_redirect!
    expect(response.body).to include("Login/Register")

    complete_google_login

    expect(response).to redirect_to("/profile")
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Your profile")
  end

  it "allows authenticated users to access the placeholder profile" do
    complete_google_login
    follow_redirect!

    get "/profile"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Your profile")
  end

  it "keeps anonymous public routes accessible" do
    get "/"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ATLAS")

    get "/srd"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ATLAS SRD")

    get "/srd/"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ATLAS SRD")

    get "/status"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("status-indicator")
  end
end
