module GamesHelper
  def formatted_game_seed(game)
    format("0x%08X", game.randomization_seed)
  end
end
