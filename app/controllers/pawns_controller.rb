class PawnsController < ApplicationController
  def create
    profile = current_user.profile
    raise ActiveRecord::RecordNotFound unless profile

    @game = profile.games.find(params[:game_id])
    @game_initialization = @game.game_initialization
    return redirect_to(root_path, status: :see_other) unless @game_initialization

    @candidate_attributes = pawn_params.to_h
    @candidate = CrewHiring.call(game: @game, candidate_attributes: @candidate_attributes)
    if @candidate.persisted?
      redirect_to game_initialization_path(@game), status: :see_other
    else
      @game_initialization.reload
      @pawns = @game.pawns.order(:id)
      render "game_initializations/show", status: :unprocessable_content
    end
  end

  private

  def pawn_params
    params.require(:pawn).permit(
      :first_name,
      :nickname,
      :last_name,
      :max_health,
      :max_stamina,
      :max_vigor,
      :starting_budget
    )
  end
end
