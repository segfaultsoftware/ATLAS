require "rails_helper"

RSpec.describe CelestialBody, type: :model do
  it "has at most one celestial transit" do
    body = FactoryBot.create(:celestial_body)
    transit = FactoryBot.create(:celestial_transit, celestial_body: body)

    expect(body.reload.celestial_transit).to eq(transit)
    expect(body).to respond_to(:celestial_transit=)
  end

  it "rejects a second transit for the same body" do
    body = FactoryBot.create(:celestial_body)
    FactoryBot.create(:celestial_transit, celestial_body: body)
    duplicate = FactoryBot.build(:celestial_transit, celestial_body: body)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors.of_kind?(:celestial_body_id, :taken)).to be(true)
  end
end
