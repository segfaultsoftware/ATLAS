class GameInitializationsController < ApplicationController
  def show
    profile = current_user.profile
    raise ActiveRecord::RecordNotFound unless profile

    @game = profile.games.find(params[:game_id])
    @game_initialization = @game.game_initialization
    return redirect_to(root_path, status: :see_other) unless @game_initialization

    @pawns = @game.pawns.order(:id)
  end
end
