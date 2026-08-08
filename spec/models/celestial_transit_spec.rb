require "rails_helper"

RSpec.describe CelestialTransit, type: :model do
  let(:start_coordinates) { { "x" => -24.433, "y" => 1399.787 } }
  let(:target_coordinates) { { "x" => -1285.575, "y" => -1532.089 } }

  it "persists Cartesian start and target coordinates" do
    transit = FactoryBot.create(
      :celestial_transit,
      celestial_coordinates_start: start_coordinates,
      celestial_coordinates_target: target_coordinates
    )

    expect(transit.reload).to have_attributes(
      celestial_coordinates_start: start_coordinates,
      celestial_coordinates_target: target_coordinates
    )
  end

  it "rejects equal start and target coordinates" do
    transit = FactoryBot.build(
      :celestial_transit,
      celestial_coordinates_start: start_coordinates,
      celestial_coordinates_target: start_coordinates
    )

    expect(transit).not_to be_valid
    expect(transit.errors.of_kind?(:celestial_coordinates_target, :equal_to_start)).to be(true)
  end

  it "allows endpoints to coincide with existing map objects" do
    transit = FactoryBot.build(
      :celestial_transit,
      celestial_coordinates_start: start_coordinates,
      celestial_coordinates_target: { "x" => 140.0, "y" => 0.0 }
    )

    expect(transit).to be_valid
  end

  it "enforces the one-transit relationship at the database level" do
    body = FactoryBot.create(:celestial_body)
    FactoryBot.create(:celestial_transit, celestial_body: body)

    expect {
      described_class.insert!({
        celestial_body_id: body.id,
        celestial_coordinates_start: start_coordinates,
        celestial_coordinates_target: target_coordinates,
        created_at: Time.current,
        updated_at: Time.current
      })
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
