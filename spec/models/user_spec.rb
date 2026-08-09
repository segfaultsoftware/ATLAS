require "rails_helper"

RSpec.describe User, type: :model do
  it "uses local password authentication with remember-me support" do
    user = FactoryBot.build(:user, email: "player@example.com", name: "Atlas Player")

    expect(user).to be_valid
    expect(described_class.devise_modules).to include(
      :database_authenticatable,
      :registerable,
      :rememberable
    )
    expect(user.encrypted_password).to be_present
    expect(user.encrypted_password).not_to include("password123")
    expect(user).to respond_to(:password=)
  end

  it "normalizes email addresses before validation" do
    user = FactoryBot.build(:user, email: "  PLAYER@EXAMPLE.COM ")

    expect(user).to be_valid
    expect(user.email).to eq("player@example.com")
  end

  it "rejects case-variant duplicate email addresses" do
    FactoryBot.create(:user, uid: "google-123", email: "first@example.com")

    duplicate = FactoryBot.build(
      :user,
      uid: "google-456",
      email: "FIRST@EXAMPLE.COM"
    )

    expect(duplicate).not_to be_valid
    expect(duplicate.errors.of_kind?(:email, :taken)).to be(true)
  end

  it "backs email normalization with a unique database index" do
    email_index = described_class.connection.indexes(:users).find do |index|
      index.name == "index_users_on_lower_email"
    end

    expect(email_index.unique).to be(true)
    expect(email_index.columns).to eq("LOWER(email)")
  end

  it "does not persist a user when its profile fails validation" do
    user = FactoryBot.build(:user)
    user.build_profile(preferred_name: user.preferred_name, avatar_key: "invalid")

    expect do
      expect(user).not_to be_valid
      user.save
    end.not_to change(described_class, :count)

    expect(user).not_to be_persisted
    expect(Profile.where(preferred_name: user.preferred_name)).to be_empty
  end

  it "owns one app-facing profile separately from Google identity data" do
    user = FactoryBot.create(:user)

    profile = user.create_profile!(preferred_name: "Pilot")

    expect(user.profile).to eq(profile)
    expect(profile.user).to eq(user)
  end

  it "defaults users to the User role" do
    user = FactoryBot.create(:user)

    expect(user.reload.role).to eq("user")
    expect(user).to be_user
    expect(user).not_to be_webadmin
  end

  it "supports promoting a user to Webadmin" do
    user = FactoryBot.create(:user, role: :webadmin)

    expect(user).to be_webadmin
    expect(user.role).to eq("webadmin")
  end
end
