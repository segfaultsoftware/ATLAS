FactoryBot.define do
  factory :game_initialization do
    association :game
    remaining_budget { 5000 }

    initialize_with { game.game_initialization || new }
  end
end
