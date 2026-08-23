require "rails_helper"

RSpec.describe "Game initializations", type: :request do
  include Devise::Test::IntegrationHelpers

  def parsed_response
    Nokogiri::HTML(response.body)
  end

  it "shows an initialized Game and its persisted remaining budget to its owner" do
    user = FactoryBot.create(:user)
    profile = FactoryBot.create(:profile, user: user)
    game = FactoryBot.create(:game, profile: profile)
    initialization = FactoryBot.create(:game_initialization, game: game, remaining_budget: 4321)
    sign_in user

    get "/games/#{game.id}/initialization"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Select Your Crew")
    expect(response.body).to include(initialization.remaining_budget.to_s)
  end

  it "renders one server-backed default candidate with only the approved hiring inputs" do
    user = FactoryBot.create(:user)
    profile = FactoryBot.create(:profile, user: user)
    game = FactoryBot.create(:game, profile: profile)
    game.game_initialization.update!(remaining_budget: 4300)
    sign_in user

    get "/games/#{game.id}/initialization"

    candidate = parsed_response.at_css(".crew-card--candidate")
    expect(candidate).to be_present
    expect(parsed_response.css(".crew-card--candidate").length).to eq(1)
    expect(candidate.at_css("form") ["action"]).to eq("/games/#{game.id}/pawns")
    expect(candidate.at_css("form") ["method"]).to eq("post")
    expect(candidate.css("input[name^='pawn[']").map { |input| input["name"] }).to contain_exactly(
      "pawn[first_name]",
      "pawn[nickname]",
      "pawn[last_name]",
      "pawn[max_health]",
      "pawn[max_stamina]",
      "pawn[max_vigor]",
      "pawn[starting_budget]"
    )
    expect(candidate.at_css("input[name='pawn[first_name]']") ["required"]).to eq("required")
    expect(candidate.css("input[type='text']").map { |input| input["maxlength"] }).to all(eq("18"))
    expect(candidate.at_css("input[name='pawn[starting_budget]']") ["value"]).to eq("4300")
    expect(candidate.text.squish).to include("Current Age: 16.00", "Health 100", "Stamina 100", "Vigor 100")
  end

  it "redirects anonymous requests to root" do
    game = FactoryBot.create(:game)

    get "/games/#{game.id}/initialization"

    expect(response).to redirect_to("/")
    expect(response).to have_http_status(:see_other)
  end

  it "does not expose another profile's Game" do
    user = FactoryBot.create(:user)
    FactoryBot.create(:profile, user: user)
    other_game = FactoryBot.create(:game)
    sign_in user

    get "/games/#{other_game.id}/initialization"

    expect(response).to have_http_status(:not_found)
  end

  it "redirects a legacy Game without initialization to root" do
    user = FactoryBot.create(:user)
    profile = FactoryBot.create(:profile, user: user)
    legacy_game = FactoryBot.create(:game, profile: profile)
    legacy_game.game_initialization.destroy!
    sign_in user

    get "/games/#{legacy_game.id}/initialization"

    expect(response).to redirect_to("/")
    expect(response).to have_http_status(:see_other)
  end

  it "renders hired pawns in stable order with text-only names and stats" do
    user = FactoryBot.create(:user)
    profile = FactoryBot.create(:profile, user: user)
    game = FactoryBot.create(:game, profile: profile)
    first_pawn = FactoryBot.create(
      :pawn,
      game: game,
      first_name: "Ada",
      nickname: "Ace",
      last_name: "Lovelace",
      max_health: 120,
      current_health: 110,
      max_stamina: 130,
      current_stamina: 125,
      max_vigor: 140,
      current_vigor: 135
    )
    second_pawn = FactoryBot.create(:pawn, game: game, first_name: "Grace", nickname: "Compiler")
    sign_in user

    get "/games/#{game.id}/initialization"

    cards = parsed_response.css(".crew-card--hired")
    expect(cards.map { |card| card["id"] }).to eq([ "pawn_#{first_pawn.id}", "pawn_#{second_pawn.id}" ])
    expect(cards.first.at_css(".crew-card__names").text.squish).to eq('Ada “Ace” Lovelace')
    expect(cards.first.text.squish).to include(
      "Maximum Health 120",
      "Current Health 110",
      "Maximum Stamina 130",
      "Current Stamina 125",
      "Maximum Vigor 140",
      "Current Vigor 135"
    )
    expect(cards.first.css("input, button, select, textarea")).to be_empty
  end
end
