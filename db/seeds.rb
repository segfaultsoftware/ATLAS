# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
landing_page = ManualPage.find_or_initialize_by(slug: "index")
landing_page.title = "ATLAS SRD" if landing_page.new_record?
landing_page.save!
ManualPageImporter.call(
  page: landing_page,
  source_path: Rails.root.join("docs/srd/atlas-srd.md")
)

ship = CelestialBody.find_or_initialize_by(name: "Ship")
ship.save!

tejat_c = Astrogation::System.entities.find { |entity| entity[:name] == "Tejat C" }
ketrak_station = Astrogation::System.entities.find { |entity| entity[:name] == "Ketrak Station" }

ship_transit = CelestialTransit.find_or_initialize_by(celestial_body: ship)
ship_transit.celestial_coordinates_start = tejat_c.slice(:x, :y)
ship_transit.celestial_coordinates_target = ketrak_station.slice(:x, :y)
ship_transit.save!
