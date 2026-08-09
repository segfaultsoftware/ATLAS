require "rails_helper"

RSpec.describe "Profile access", type: :request do
  include Devise::Test::IntegrationHelpers

  def complete_local_login(user)
    post "/users/sign_in",
         params: {
           user: {
             email: user.email,
             password: "password123"
           }
         }
  end

  it "blocks anonymous current-profile access and stores the intended destination for login" do
    get "/profile"

    expect(response).to redirect_to("/")
    follow_redirect!
    expect(response.body).to include("Log in")
    expect(response.body).to include("Sign up")

    user = FactoryBot.create(:user)
    FactoryBot.create(:profile, user: user)
    complete_local_login(user)

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
    expect(response.body).to include("Log in")
    expect(response.body).to include("Sign up")

    user = FactoryBot.create(:user)
    complete_local_login(user)

    expect(response).to redirect_to("/profiles/#{profile.id}")
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Other Pilot")
  end

  it "allows authenticated users to view their own read-only profile data" do
    user = FactoryBot.create(:user)
    profile = FactoryBot.create(:profile, user: user, preferred_name: "Atlas Player")
    complete_local_login(user)
    profile.update!(
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
    user = FactoryBot.create(:user)
    FactoryBot.create(:profile, user: user)
    complete_local_login(user)

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
