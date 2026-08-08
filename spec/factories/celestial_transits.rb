FactoryBot.define do
  factory :celestial_transit do
    association :celestial_body
    celestial_coordinates_start { { "x" => -24.433, "y" => 1399.787 } }
    celestial_coordinates_target { { "x" => -1285.575, "y" => -1532.089 } }
  end
end
