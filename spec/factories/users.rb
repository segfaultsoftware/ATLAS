FactoryBot.define do
  factory :user do
    sequence(:email) { |number| "player#{number}@example.com" }
    name { "Atlas Player" }
    password { "password123" }
    password_confirmation { password }
  end
end
