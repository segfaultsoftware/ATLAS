require "rails_helper"

RSpec.describe "Profile editing", type: :request do
  include Devise::Test::IntegrationHelpers

  it "blocks anonymous profile edit access" do
    get "/profile/edit"

    expect(response).to redirect_to("/")
    follow_redirect!
    expect(response.body).to include("Login")
    expect(response.body).to include("Register")
  end

  it "blocks anonymous profile update attempts" do
    patch "/profile",
          params: {
            profile: {
              preferred_name: "Signal Pilot"
            }
          }

    expect(response).to redirect_to("/")
    follow_redirect!
    expect(response.body).to include("Login")
    expect(response.body).to include("Register")
  end

  it "shows read-only profile data by default with an edit action for the current user" do
    user = FactoryBot.create(:user, name: "Atlas Player")
    FactoryBot.create(
      :profile,
      user: user,
      preferred_name: "Atlas Player",
      pronouns: "they/them",
      preferred_playtimes: "Weeknights",
      avatar_key: "cry"
    )
    sign_in user

    get "/profile"

    expect(response).to have_http_status(:ok)
    profile_page = Nokogiri::HTML(response.body).at_css(".profile-page")
    edit_link = profile_page.at_css('a[href="/profile/edit"]')
    expect(edit_link.text).to include("Edit profile")
    expect(profile_page.css("input, textarea, select")).to be_empty
    expect(profile_page.text).to include("Atlas Player")
    expect(profile_page.text).to include("they/them")
    expect(profile_page.text).to include("Weeknights")
    expect(profile_page.text).to include("cry")
  end

  it "exposes editable profile fields and avatar selection for the current user" do
    user = FactoryBot.create(:user)
    FactoryBot.create(:profile, user: user)
    sign_in user

    get "/profile/edit"

    expect(response).to have_http_status(:ok)
    form = Nokogiri::HTML(response.body).at_css("form.profile-form")
    expect(form["action"]).to eq("/profile")
    expect(form.at_css('input[name="_method"][value="patch"]')).to be_present
    expect(form.at_css('input[name="profile[preferred_name]"]')).to be_present
    expect(form.at_css('input[name="profile[pronouns]"]')).to be_present
    expect(form.at_css('textarea[name="profile[preferred_playtimes]"]')).to be_present
    expect(form.css('input[name="profile[avatar_key]"]').map { |input| input["value"] })
      .to match_array(Profile.avatar_options.keys)
    expect(form.at_css('button[type="submit"]').text).to include("Save profile")
  end

  it "saves allowed profile changes and returns to read-only display" do
    user = FactoryBot.create(:user)
    profile = FactoryBot.create(:profile, user: user)
    sign_in user

    patch "/profile",
          params: {
            profile: {
              preferred_name: "Signal Pilot",
              pronouns: "she/her",
              preferred_playtimes: "Sundays after noon",
              avatar_key: "frown"
            }
          }

    expect(response).to redirect_to("/profile")
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Signal Pilot")
    expect(response.body).to include("she/her")
    expect(response.body).to include("Sundays after noon")
    expect(response.body).to include("frown")
    expect(Nokogiri::HTML(response.body).at_css(".profile-page").css("input, textarea, select")).to be_empty

    expect(profile.reload.preferred_name).to eq("Signal Pilot")
    expect(profile.pronouns).to eq("she/her")
    expect(profile.preferred_playtimes).to eq("Sundays after noon")
    expect(profile.avatar_key).to eq("frown")
  end

  it "renders edit mode with errors when preferred playtimes is too long" do
    user = FactoryBot.create(:user)
    profile = FactoryBot.create(:profile, user: user, preferred_playtimes: "Sundays")
    sign_in user

    patch "/profile",
          params: {
            profile: {
              preferred_name: "Signal Pilot",
              preferred_playtimes: "a" * 257,
              avatar_key: "smile"
            }
          }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Preferred playtimes is too long")
    expect(response.body).to include("Save profile")
    expect(profile.reload.preferred_playtimes).not_to eq("a" * 257)
  end

  it "does not allow profile ownership to be reassigned through edits" do
    user = FactoryBot.create(:user)
    profile = FactoryBot.create(:profile, user: user)
    other_user = FactoryBot.create(:user)
    sign_in user

    patch "/profile",
          params: {
            profile: {
              preferred_name: "Signal Pilot",
              user_id: other_user.id
            }
          }

    expect(response).to redirect_to("/profile")
    expect(profile.reload.user).to eq(user)
    expect(profile.preferred_name).to eq("Signal Pilot")
  end
end
