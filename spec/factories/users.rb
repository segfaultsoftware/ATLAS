FactoryBot.define do
  factory :user do
    provider { "google_oauth2" }
    sequence(:uid) { |number| "google-#{number}" }
    sequence(:email) { |number| "player#{number}@example.com" }
    name { "Atlas Player" }
    preferred_name { "Atlas Player" }
    password { "password123" }
    password_confirmation { password }
  end
end
