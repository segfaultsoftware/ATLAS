class GamesController < ApplicationController
  before_action :ensure_current_profile

  def index
    load_games
    @game = @profile.games.build
  end

  def create
    @game = @profile.games.build(game_params)

    if @game.save
      load_games
      @game = @profile.games.build

      respond_to do |format|
        format.html { redirect_to games_path, status: :see_other }
        format.turbo_stream
      end
    else
      load_games

      respond_to do |format|
        format.html { render :index, status: :unprocessable_content }
        format.turbo_stream { render :create, status: :unprocessable_content }
      end
    end
  end

  def destroy
    @profile.games.find(params[:id]).destroy!
    load_games
    @game = @profile.games.build

    respond_to do |format|
      format.html { redirect_to games_path, status: :see_other }
      format.turbo_stream
    end
  end

  private

  def ensure_current_profile
    @profile = current_user.profile || current_user.ensure_profile!(preferred_name: current_user.name)
  end

  def load_games
    @games = @profile.games.order(id: :desc)
  end

  def game_params
    params.require(:game).permit(:name)
  end
end
