FactoryBot.define do
  factory :manual_category do
    sequence(:name) { |number| "Category #{number}" }
    sequence(:slug) { |number| "category-#{number}" }
  end
end
