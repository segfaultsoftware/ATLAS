require "rails_helper"

RSpec.describe "Authentication routes", type: :request do
  def route_for(method, path)
    Rails.application.routes.recognize_path(path, method: method)
  end

  it "exposes local session and registration routes" do
    expect(route_for(:get, "/users/sign_in")).to include(
      controller: "devise/sessions",
      action: "new"
    )
    expect(route_for(:post, "/users/sign_in")).to include(
      controller: "devise/sessions",
      action: "create"
    )
    expect(route_for(:get, "/users/sign_up")).to include(
      controller: "users/registrations",
      action: "new"
    )
    expect(route_for(:post, "/users")).to include(
      controller: "users/registrations",
      action: "create"
    )

    expect { route_for(:get, "/users/password/new") }.to raise_error(ActionController::RoutingError)
    expect { route_for(:post, "/users/password") }.to raise_error(ActionController::RoutingError)
  end

  it "does not expose Google OAuth callback routes" do
    expect { route_for(:post, "/users/auth/google_oauth2") }.to raise_error(ActionController::RoutingError)
    expect { route_for(:get, "/users/auth/google_oauth2/callback") }.to raise_error(ActionController::RoutingError)
  end
end
