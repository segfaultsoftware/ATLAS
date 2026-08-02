FactoryBot.define do
  factory :manual_page do
    sequence(:title) { |number| "Manual Page #{number}" }
    sequence(:slug) { |number| "manual-page-#{number}" }
    content { "# Manual page" }
    parent { nil }
  end
end
