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

  it "blocks anonymous current-profile access and stores the intended destination for login" do
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

  it "blocks anonymous profile record access and stores the intended destination for login" do
    profile = FactoryBot.create(:profile, preferred_name: "Other Pilot")

    get "/profiles/#{profile.id}"

    expect(response).to redirect_to("/")
    follow_redirect!
    expect(response.body).to include("Login/Register")

    complete_google_login

    expect(response).to redirect_to("/profiles/#{profile.id}")
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Other Pilot")
  end

  it "allows authenticated users to view their own read-only profile data" do
    complete_google_login
    follow_redirect!
    User.last.profile.update!(
      pronouns: "they/them",
      preferred_playtimes: "Weeknights after 7",
      avatar_key: "smile"
    )

    get "/profile"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Your profile")
    expect(response.body).to include("Atlas Player")
    expect(response.body).to include("they/them")
    expect(response.body).to include("Weeknights after 7")
    expect(response.body).to include("smile")
    profile_page = Nokogiri::HTML(response.body).at_css(".profile-page")
    expect(profile_page.css("input, textarea, select")).to be_empty
  end

  it "allows authenticated users to view another user's profile" do
    other_profile = FactoryBot.create(
      :profile,
      preferred_name: "Signal Weaver",
      pronouns: "she/her",
      preferred_playtimes: "Sundays",
      avatar_key: "frown"
    )
    complete_google_login
    follow_redirect!

    get "/profiles/#{other_profile.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Signal Weaver")
    expect(response.body).to include("she/her")
    expect(response.body).to include("Sundays")
    expect(response.body).to include("frown")
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
