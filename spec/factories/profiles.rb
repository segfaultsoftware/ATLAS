FactoryBot.define do
  factory :profile do
    association :user
    pronouns { "they/them" }
    preferred_playtimes { "Weeknights after 7" }
    avatar_key { "smile" }
  end
end
