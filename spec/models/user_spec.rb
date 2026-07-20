require "rails_helper"

RSpec.describe User, type: :model do
  it "uses Google OAuth identity fields without password authentication" do
    user = build(:user, uid: "google-123", email: "player@example.com", name: "Atlas Player")

    expect(user).to be_valid
    expect(described_class.devise_modules).to include(:omniauthable, :rememberable)
    expect(described_class.devise_modules).not_to include(
      :database_authenticatable,
      :registerable,
      :recoverable,
      :validatable
    )
    expect(user).not_to respond_to(:password=)
  end

  it "requires each Google provider uid to be unique" do
    create(:user, uid: "google-123", email: "first@example.com")

    duplicate = build(
      :user,
      uid: "google-123",
      email: "second@example.com"
    )

    expect(duplicate).not_to be_valid
    expect(duplicate.errors.of_kind?(:uid, :taken)).to be(true)
  end

  it "owns one app-facing profile separately from Google identity data" do
    user = create(:user)

    profile = user.create_profile!(preferred_name: "Pilot")

    expect(user.profile).to eq(profile)
    expect(profile.user).to eq(user)
  end
end
