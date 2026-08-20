require "rails_helper"

RSpec.describe Profile, type: :model do
  it "stores app-facing profile fields separately from Google identity fields" do
    profile = FactoryBot.build(:profile)

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
    user = FactoryBot.create(:user)

    profile = FactoryBot.create(:profile, user: user, preferred_name: "Pilot")
    duplicate = FactoryBot.build(:profile, user: user, preferred_name: "Navigator")

    expect(user.reload.profile).to eq(profile)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors.of_kind?(:user_id, :taken)).to be(true)
  end

  it "owns games and destroys them with the profile" do
    profile = FactoryBot.create(:profile)
    game = FactoryBot.create(:game, profile: profile)

    expect(profile.games).to contain_exactly(game)

    profile.destroy!

    expect(Game.exists?(game.id)).to be(false)
  end

  it "allows blank preferred playtimes" do
    profile = FactoryBot.build(:profile, preferred_playtimes: "")

    expect(profile).to be_valid
  end

  it "limits preferred playtimes to 256 characters" do
    profile = FactoryBot.build(:profile, preferred_playtimes: "a" * 257)

    expect(profile).not_to be_valid
    expect(profile.errors.of_kind?(:preferred_playtimes, :too_long)).to be(true)
  end

  it "allows only the fixed emoji avatar keys" do
    expect(Profile.avatar_options).to include(
      "smile" => "🙂",
      "frown" => "🙁",
      "cry" => "😢"
    )

    Profile.avatar_options.each_key do |avatar_key|
      profile = FactoryBot.build(:profile, avatar_key: avatar_key)

      expect(profile).to be_valid
    end
  end

  it "rejects avatar keys outside the fixed set" do
    profile = FactoryBot.build(:profile, avatar_key: "custom-upload")

    expect(profile).not_to be_valid
    expect(profile.errors.of_kind?(:avatar_key, :inclusion)).to be(true)
  end

  it "stores the default avatar key when avatar selection is blank" do
    profile = FactoryBot.build(:profile, avatar_key: "")

    expect(profile).to be_valid
    expect(profile.avatar_key).to eq(Profile::DEFAULT_AVATAR_KEY)
  end

  it "returns the default emoji when no avatar is selected" do
    profile = FactoryBot.build(:profile, avatar_key: nil)

    expect(profile.avatar_emoji).to eq(Profile.avatar_options.fetch(Profile::DEFAULT_AVATAR_KEY))
  end
end
