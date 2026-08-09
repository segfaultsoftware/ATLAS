require "rails_helper"

RSpec.describe "Devise configuration" do
  it "does not register Google OAuth or require OAuth credentials" do
    expect(Devise.omniauth_configs).not_to have_key(:google_oauth2)

    initializer = Rails.root.join("config/initializers/devise.rb").read
    expect(initializer).not_to include("GOOGLE_OAUTH_CLIENT_ID")
    expect(initializer).not_to include("GOOGLE_OAUTH_CLIENT_SECRET")
  end
end
