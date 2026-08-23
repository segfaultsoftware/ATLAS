require "rails_helper"

RSpec.describe "Pawn hiring", type: :request do
  include Devise::Test::IntegrationHelpers

  def valid_pawn_params(overrides = {})
    {
      first_name: "Ada",
      nickname: "Ace",
      last_name: "Lovelace",
      max_health: 110,
      max_stamina: 100,
      max_vigor: 100,
      starting_budget: 5000
    }.merge(overrides)
  end

  it "exposes only the nested create route" do
    routes = Rails.application.routes

    expect(routes.recognize_path("/games/1/pawns", method: :post))
      .to include(controller: "pawns", action: "create", game_id: "1")
    expect { routes.recognize_path("/games/1/pawns", method: :get) }
      .to raise_error(ActionController::RoutingError)
  end

  it "redirects an anonymous hire without persisting a Pawn" do
    game = FactoryBot.create(:game)

    expect do
      post "/games/#{game.id}/pawns", params: { pawn: valid_pawn_params }
    end.not_to change(Pawn, :count)

    expect(response).to redirect_to("/")
  end

  it "does not expose another Profile's Game" do
    user = FactoryBot.create(:user)
    FactoryBot.create(:profile, user: user)
    other_game = FactoryBot.create(:game)
    sign_in user

    expect do
      post "/games/#{other_game.id}/pawns", params: { pawn: valid_pawn_params }
    end.not_to change(Pawn, :count)

    expect(response).to have_http_status(:not_found)
  end

  it "redirects a legacy Game without creating a Pawn" do
    user = FactoryBot.create(:user)
    profile = FactoryBot.create(:profile, user: user)
    game = FactoryBot.create(:game, profile: profile)
    game.game_initialization.destroy!
    sign_in user

    expect do
      post "/games/#{game.id}/pawns", params: { pawn: valid_pawn_params }
    end.not_to change(Pawn, :count)

    expect(response).to redirect_to("/")
    expect(response).to have_http_status(:see_other)
  end

  it "hires a Pawn and redirects to the initialization page" do
    user = FactoryBot.create(:user)
    profile = FactoryBot.create(:profile, user: user)
    game = FactoryBot.create(:game, profile: profile)
    sign_in user

    expect do
      post "/games/#{game.id}/pawns", params: {
        pawn: valid_pawn_params(
          born_on_turn: -1,
          current_health: 1,
          current_stamina: 1,
          current_vigor: 1,
          age: 99,
          cost: 0,
          remaining_budget: 5000
        )
      }
    end.to change(game.pawns, :count).by(1)

    pawn = game.pawns.order(:id).last
    expect(pawn).to have_attributes(
      born_on_turn: -97_500_000,
      max_health: 110,
      current_health: 110,
      current_stamina: 100,
      current_vigor: 100
    )
    expect(game.game_initialization.reload.remaining_budget).to eq(4900)
    expect(response).to redirect_to("/games/#{game.id}/initialization")
    expect(response).to have_http_status(:see_other)
  end

  it "returns a controlled failure with submitted candidate state and unchanged persistence" do
    user = FactoryBot.create(:user)
    profile = FactoryBot.create(:profile, user: user)
    game = FactoryBot.create(:game, profile: profile)
    sign_in user

    expect do
      post "/games/#{game.id}/pawns", params: {
        pawn: valid_pawn_params(first_name: "  Retained  ", max_health: 105)
      }
    end.not_to change(Pawn, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Unable to hire candidate", "Retained", "105")
    expect(game.game_initialization.reload.remaining_budget).to eq(5000)
  end
end
