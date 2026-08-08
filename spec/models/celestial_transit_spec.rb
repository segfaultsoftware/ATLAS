require "rails_helper"

RSpec.describe CelestialTransit, type: :model do
  describe "associations" do
    it "belongs to a celestial body" do
      transit = FactoryBot.build(:celestial_transit)

      expect(transit.celestial_body).to be_a(CelestialBody)
    end

    it "rejects a second transit for the same body" do
      body = FactoryBot.create(:celestial_body)
      FactoryBot.create(:celestial_transit, celestial_body: body)
      duplicate = FactoryBot.build(:celestial_transit, celestial_body: body)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:celestial_body_id]).to include("has already been taken")
    end

    it "enforces one transit per body at the database level" do
      body = FactoryBot.create(:celestial_body)
      transit = FactoryBot.create(:celestial_transit, celestial_body: body)
      duplicate = transit.dup

      expect do
        duplicate.save!(validate: false)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "coordinate validation" do
    it "persists separate numeric start and target coordinates" do
      transit = FactoryBot.create(
        :celestial_transit,
        celestial_coordinates_start_x: -24.433,
        celestial_coordinates_start_y: 1399.787,
        celestial_coordinates_target_x: -1285.575,
        celestial_coordinates_target_y: -1532.089
      )

      expect(transit.reload.attributes).to include(
        "celestial_coordinates_start_x" => -24.433,
        "celestial_coordinates_start_y" => 1399.787,
        "celestial_coordinates_target_x" => -1285.575,
        "celestial_coordinates_target_y" => -1532.089
      )
    end

    it "rejects identical start and target coordinates" do
      transit = FactoryBot.build(
        :celestial_transit,
        celestial_coordinates_start_x: 12.5,
        celestial_coordinates_start_y: -7.25,
        celestial_coordinates_target_x: 12.5,
        celestial_coordinates_target_y: -7.25
      )

      expect(transit).not_to be_valid
      expect(transit.errors[:base]).to include("start and target coordinates must differ")
    end

    it "allows a start endpoint to overlap an existing map coordinate" do
      map_entity = Astrogation::System.entities.find { |entity| entity[:name] == "Tejat A" }
      transit = FactoryBot.build(
        :celestial_transit,
        celestial_coordinates_start_x: map_entity.fetch(:x),
        celestial_coordinates_start_y: map_entity.fetch(:y)
      )

      expect(transit).to be_valid
    end
  end
end
