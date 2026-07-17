require "rails_helper"

RSpec.describe "Devise configuration" do
  it "registers Google OAuth from environment-backed credentials" do
    expect(Devise.omniauth_configs).to have_key(:google_oauth2)

    initializer = Rails.root.join("config/initializers/devise.rb").read
    expect(initializer).to include('ENV.fetch("GOOGLE_OAUTH_CLIENT_ID", nil)')
    expect(initializer).to include('ENV.fetch("GOOGLE_OAUTH_CLIENT_SECRET", nil)')
    expect(initializer).not_to match(/AIza|GOCSPX-|\.apps\.googleusercontent\.com/)
  end
end
