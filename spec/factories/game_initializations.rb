FactoryBot.define do
  factory :game_initialization do
    association :game
    remaining_budget { 5000 }

    initialize_with { game.game_initialization || game.build_game_initialization }
  end
end
