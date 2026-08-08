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

origin = Astrogation::System.entities.find { |entity| entity[:name] == "Tejat C" }
destination = Astrogation::System.entities.find { |entity| entity[:name] == "Ketrak Station" }
transit = ship.celestial_transit || ship.build_celestial_transit
transit.assign_attributes(
  celestial_coordinates_start_x: origin.fetch(:x),
  celestial_coordinates_start_y: origin.fetch(:y),
  celestial_coordinates_target_x: destination.fetch(:x),
  celestial_coordinates_target_y: destination.fetch(:y)
)
transit.save!
