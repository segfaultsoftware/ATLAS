require "rails_helper"

RSpec.describe "Status", type: :request do
  it "renders the public status thumb" do
    get "/status"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("status-thumb")
    expect(response.body).to include('data-controller="status-thumb"')
    expect(response.body).to include("\u{1F44D}")
  end
end
