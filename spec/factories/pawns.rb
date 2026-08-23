FactoryBot.define do
  factory :pawn do
    association :game
    first_name { "Ada" }
    last_name { "Lovelace" }
    nickname { "Enchantress" }
    born_on_turn { -96_000_000 }
    max_health { 100 }
    current_health { 100 }
    max_stamina { 100 }
    current_stamina { 100 }
    max_vigor { 100 }
    current_vigor { 100 }
  end
end
