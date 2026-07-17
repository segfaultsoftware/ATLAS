require "rails_helper"

RSpec.describe "Landing", type: :request do
  it "renders the public ATLAS landing page" do
    get "/"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<h1 id="landing-title">ATLAS</h1>')
  end
end
