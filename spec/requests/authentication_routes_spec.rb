require "rails_helper"

RSpec.describe "Authentication routes", type: :request do
  def route_for(method, path)
    Rails.application.routes.recognize_path(path, method: method)
  end

  it "exposes Google OAuth routes without email or password authentication routes" do
    expect(route_for(:post, "/users/auth/google_oauth2")).to include(
      controller: "users/omniauth_callbacks",
      action: "passthru"
    )
    expect(route_for(:get, "/users/auth/google_oauth2/callback")).to include(
      controller: "users/omniauth_callbacks",
      action: "google_oauth2"
    )

    expect { route_for(:get, "/users/sign_in") }.to raise_error(ActionController::RoutingError)
    expect { route_for(:post, "/users/sign_in") }.to raise_error(ActionController::RoutingError)
    expect { route_for(:get, "/users/sign_up") }.to raise_error(ActionController::RoutingError)
    expect { route_for(:post, "/users") }.to raise_error(ActionController::RoutingError)
    expect { route_for(:get, "/users/password/new") }.to raise_error(ActionController::RoutingError)
    expect { route_for(:post, "/users/password") }.to raise_error(ActionController::RoutingError)
  end
end
