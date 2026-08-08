require "rails_helper"

RSpec.describe "Celestial seed data", type: :request do
  it "creates the ship transit idempotently" do
    2.times { load Rails.root.join("db/seeds.rb") }

    ship = CelestialBody.find_by!(name: "Ship")
    transit = ship.celestial_transit

    expect(CelestialBody.where(name: "Ship").count).to eq(1)
    expect(CelestialTransit.where(celestial_body: ship).count).to eq(1)
    expect(transit).to have_attributes(
      celestial_coordinates_start: { "x" => -24.433, "y" => 1399.787 },
      celestial_coordinates_target: { "x" => -1285.575, "y" => -1532.089 }
    )
  end
end
