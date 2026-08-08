FactoryBot.define do
  factory :celestial_body do
    sequence(:name) { |number| "Celestial Body #{number}" }
  end
end
