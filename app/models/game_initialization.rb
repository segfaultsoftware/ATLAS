class GameInitialization < ApplicationRecord
  belongs_to :game, inverse_of: :game_initialization

  validates :remaining_budget,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
