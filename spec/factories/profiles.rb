FactoryBot.define do
  factory :profile do
    association :user
    preferred_name { "Starhand" }
    pronouns { "they/them" }
    preferred_playtimes { "Weeknights after 7" }
    avatar_key { "smile" }
  end
end
