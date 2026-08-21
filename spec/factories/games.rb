FactoryBot.define do
  factory :game do
    association :profile
    name { "Voyager" }
  end
end
