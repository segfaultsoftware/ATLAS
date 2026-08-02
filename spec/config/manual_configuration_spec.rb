require "rails_helper"

RSpec.describe "Manual configuration" do
  it "provides the configured landing-page slug" do
    expect(Rails.configuration.x.manual.landing_page_slug).to eq("index")
  end
end
