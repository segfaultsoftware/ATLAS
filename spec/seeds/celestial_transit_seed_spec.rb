require "rails_helper"

RSpec.describe "Celestial transit seeds", type: :model do
  def load_seeds
    load Rails.root.join("db/seeds.rb")
  end

  it "creates the ship transit idempotently from Tejat C to Ketrak Station" do
    load_seeds
    load_seeds

    ship = CelestialBody.find_by!(name: "Ship")
    transit = ship.celestial_transit
    origin = Astrogation::System.entities.find { |entity| entity[:name] == "Tejat C" }
    destination = Astrogation::System.entities.find { |entity| entity[:name] == "Ketrak Station" }

    expect(CelestialBody.where(name: "Ship").count).to eq(1)
    expect(CelestialTransit.where(celestial_body: ship).count).to eq(1)
    expect(transit).to have_attributes(
      celestial_coordinates_start_x: origin.fetch(:x),
      celestial_coordinates_start_y: origin.fetch(:y),
      celestial_coordinates_target_x: destination.fetch(:x),
      celestial_coordinates_target_y: destination.fetch(:y)
    )
  end
end
