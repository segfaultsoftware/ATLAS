require "rails_helper"

RSpec.describe Astrogation::System, type: :service do
  describe ".entities" do
    it "returns the seven deterministic system entities" do
      expect(described_class.entities.map { |entity| entity.slice(:name, :kind, :x, :y) }).to eq(
        [
          { name: "Tejat A", kind: "planet", x: 140.0, y: 0.0 },
          { name: "Tejat B", kind: "planet", x: 553.892, y: 534.887 },
          { name: "Tejat C", kind: "planet", x: -24.433, y: 1399.787 },
          { name: "Ketrak Station", kind: "station", x: -1285.575, y: -1532.089 },
          { name: "Gate Alpha", kind: "gate", x: 2500.0, y: 0.0 },
          { name: "Gate Beta", kind: "gate", x: -2500.0, y: 0.0 },
          { name: "Ship", kind: "ship", x: -402.776, y: 520.224 }
        ]
      )
    end

    it "returns immutable data" do
      expect(described_class.entities).to be_frozen
      expect(described_class.entities).to all(be_frozen)
    end
  end

  describe ".transits" do
    it "returns every persisted transit with Cartesian endpoint objects" do
      FactoryBot.create(
        :celestial_transit,
        celestial_coordinates_start_x: -24.433,
        celestial_coordinates_start_y: 1399.787,
        celestial_coordinates_target_x: -1285.575,
        celestial_coordinates_target_y: -1532.089
      )
      FactoryBot.create(
        :celestial_transit,
        celestial_coordinates_start_x: 10.0,
        celestial_coordinates_start_y: 20.0,
        celestial_coordinates_target_x: 30.0,
        celestial_coordinates_target_y: 40.0
      )

      expect(described_class.transits).to eq(
        [
          {
            celestial_coordinates_start: { x: -24.433, y: 1399.787 },
            celestial_coordinates_target: { x: -1285.575, y: -1532.089 }
          },
          {
            celestial_coordinates_start: { x: 10.0, y: 20.0 },
            celestial_coordinates_target: { x: 30.0, y: 40.0 }
          }
        ]
      )
    end

    it "returns immutable data" do
      FactoryBot.create(:celestial_transit)

      expect(described_class.transits).to be_frozen
      expect(described_class.transits).to all(be_frozen)
    end
  end

  describe ".coordinate" do
    it "uses clockwise angles as positive screen Y" do
      expect(described_class.coordinate(distance: 100, angle: 90)).to eq({ x: 0.0, y: 100.0 })
    end
  end

  it "places the ship exactly thirty percent from Tejat C toward Ketrak Station" do
    ship = described_class.entities.find { |entity| entity[:kind] == "ship" }

    expect(ship.slice(:x, :y)).to eq({ x: -402.776, y: 520.224 })
  end
end
