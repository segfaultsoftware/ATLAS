FactoryBot.define do
  factory :celestial_transit do
    association :celestial_body
    celestial_coordinates_start_x { 1.25 }
    celestial_coordinates_start_y { -2.5 }
    celestial_coordinates_target_x { 10.75 }
    celestial_coordinates_target_y { 20.5 }
  end
end
