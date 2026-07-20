require "rails_helper"

RSpec.describe Profile, type: :model do
  it "stores app-facing profile fields separately from Google identity fields" do
    profile = build(:profile)

    expect(profile).to be_valid
    expect(profile).to respond_to(:preferred_name)
    expect(profile).to respond_to(:pronouns)
    expect(profile).to respond_to(:preferred_playtimes)
    expect(profile).to respond_to(:avatar_key)
    expect(profile).not_to respond_to(:provider)
    expect(profile).not_to respond_to(:uid)
    expect(profile).not_to respond_to(:email)
  end

  it "belongs to one auth user and lets each auth user own one profile" do
    user = create(:user)

    profile = create(:profile, user: user, preferred_name: "Pilot")
    duplicate = build(:profile, user: user, preferred_name: "Navigator")

    expect(user.reload.profile).to eq(profile)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors.of_kind?(:user_id, :taken)).to be(true)
  end

  it "allows blank preferred playtimes" do
    profile = build(:profile, preferred_playtimes: "")

    expect(profile).to be_valid
  end

  it "limits preferred playtimes to 256 characters" do
    profile = build(:profile, preferred_playtimes: "a" * 257)

    expect(profile).not_to be_valid
    expect(profile.errors.of_kind?(:preferred_playtimes, :too_long)).to be(true)
  end
end
