require "rails_helper"

RSpec.describe "Google authentication removal", type: :request do
  def route_for(method, path)
    Rails.application.routes.recognize_path(path, method: method)
  end

  it "does not expose Google OAuth routes" do
    expect { route_for(:post, "/users/auth/google_oauth2") }.to raise_error(ActionController::RoutingError)
    expect { route_for(:get, "/users/auth/google_oauth2/callback") }.to raise_error(ActionController::RoutingError)
  end

  it "does not register an OAuth provider or require OAuth credentials" do
    expect(Devise.omniauth_configs).to be_empty

    initializer = Rails.root.join("config/initializers/devise.rb").read
    expect(initializer).not_to match(/OAuth|omniauth|GOOGLE_OAUTH/i)
  end
end
