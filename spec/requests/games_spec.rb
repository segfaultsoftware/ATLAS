require "rails_helper"

RSpec.describe "Games", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:turbo_stream_headers) { { "ACCEPT" => "text/vnd.turbo-stream.html" } }

  def parsed_response
    Nokogiri::HTML(response.body)
  end

  def turbo_replacement
    Nokogiri::HTML5.fragment(response.body)
      .at_css('turbo-stream[action="replace"][target="games_content"]')
  end

  it "exposes only index, create, and destroy routes" do
    routes = Rails.application.routes

    expect(routes.recognize_path("/games", method: :get))
      .to include(controller: "games", action: "index")
    expect(routes.recognize_path("/games", method: :post))
      .to include(controller: "games", action: "create")
    expect(routes.recognize_path("/games/1", method: :delete))
      .to include(controller: "games", action: "destroy", id: "1")
    expect { routes.recognize_path("/games/1", method: :get) }
      .to raise_error(ActionController::RoutingError)
    expect { routes.recognize_path("/games/1/edit", method: :get) }
      .to raise_error(ActionController::RoutingError)
    expect { routes.recognize_path("/games/1", method: :patch) }
      .to raise_error(ActionController::RoutingError)
  end

  it "redirects anonymous index, create, and destroy requests immediately to root" do
    game = FactoryBot.create(:game)

    get "/games"
    expect(response).to redirect_to("/")

    post "/games", params: { game: { name: "Voyager" } }
    expect(response).to redirect_to("/")

    expect do
      delete "/games/#{game.id}"
    end.not_to change(Game, :count)
    expect(response).to redirect_to("/")
  end

  it "lazily creates the current profile and renders its stable Games content" do
    user = FactoryBot.create(:user, name: "Atlas Player")
    sign_in user

    expect do
      get "/games"
    end.to change(Profile, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(user.reload.profile.preferred_name).to eq("Atlas Player")
    expect(parsed_response.at_css("#games_content")).to be_present
  end

  it "lists only current-profile Games newest first with boundary seeds formatted as eight uppercase digits" do
    user = FactoryBot.create(:user)
    profile = FactoryBot.create(:profile, user: user)
    other_profile = FactoryBot.create(:profile)
    allow(SecureRandom).to receive(:random_number).with(2**32).and_return(0, 123, 4_294_967_295)
    older_game = FactoryBot.create(:game, profile: profile, name: "Current Older")
    other_game = FactoryBot.create(:game, profile: other_profile, name: "Other Profile Game")
    newer_game = FactoryBot.create(:game, profile: profile, name: "Current Newer")
    sign_in user

    get "/games"

    games_content = parsed_response.at_css("#games_content")
    expect(games_content.text.index(newer_game.name)).to be < games_content.text.index(older_game.name)
    expect(games_content.text).not_to include(other_game.name)
    expect(games_content.text).to include("0x00000000")
    expect(games_content.text).to include("0xFFFFFFFF")
  end

  it "creates a trimmed Game from HTML while keeping its seed server-owned" do
    user = FactoryBot.create(:user)
    profile = FactoryBot.create(:profile, user: user)
    allow(SecureRandom).to receive(:random_number).with(2**32).and_return(42)
    sign_in user

    expect do
      post "/games", params: { game: { name: "  Voyager  ", randomization_seed: 7 } }
    end.to change(profile.games, :count).by(1)
      .and change(GameInitialization, :count).by(1)

    game = profile.games.order(:id).last
    expect(response).to redirect_to("/games")
    expect(game.name).to eq("Voyager")
    expect(game.randomization_seed).to eq(42)
    expect(game.game_initialization).to be_persisted
    expect(game.game_initialization.remaining_budget).to eq(5000)
  end

  it "rolls back the game and returns a controlled failure when initialization is invalid" do
    user = FactoryBot.create(:user)
    profile = FactoryBot.create(:profile, user: user)
    allow_any_instance_of(Game).to receive(:build_game_initialization).and_wrap_original do |build_initialization|
      build_initialization.call.tap { |initialization| initialization.remaining_budget = -1 }
    end
    sign_in user

    expect do
      post "/games", params: { game: { name: "Voyager" } }
    end.to change(profile.games, :count).by(0)
      .and change(GameInitialization, :count).by(0)

    expect(response).to have_http_status(:unprocessable_content)
    expect(parsed_response.at_css('[role="alert"]')).to be_present
  end

  it "replaces Games content after Turbo create without a redirect" do
    user = FactoryBot.create(:user)
    profile = FactoryBot.create(:profile, user: user)
    sign_in user

    expect do
      post "/games", params: { game: { name: "Voyager" } }, headers: turbo_stream_headers
    end.to change(profile.games, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(turbo_replacement).to be_present
    expect(turbo_replacement.text).to include("Voyager")
  end

  it "returns retained inline create errors for HTML and Turbo requests" do
    user = FactoryBot.create(:user)
    FactoryBot.create(:profile, user: user)
    submitted_name = "x" * 65
    sign_in user

    [ {}, turbo_stream_headers ].each do |headers|
      post "/games", params: { game: { name: submitted_name } }, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      content = headers.empty? ? parsed_response.at_css("#games_content") : turbo_replacement
      expect(content).to be_present
      expect(content.at_css('form input[name="game[name]"]')["value"]).to eq(submitted_name)
      expect(content.at_css('[role="alert"]')).to be_present
    end
  end

  it "deletes only a current-profile Game with HTML and Turbo fallbacks" do
    user = FactoryBot.create(:user)
    profile = FactoryBot.create(:profile, user: user)
    html_game = FactoryBot.create(:game, profile: profile, name: "HTML Game")
    turbo_game = FactoryBot.create(:game, profile: profile, name: "Turbo Game")
    sign_in user

    expect do
      delete "/games/#{html_game.id}"
    end.to change(profile.games, :count).by(-1)
    expect(response).to redirect_to("/games")

    expect do
      delete "/games/#{turbo_game.id}", headers: turbo_stream_headers
    end.to change(profile.games, :count).by(-1)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(turbo_replacement).to be_present
    expect(turbo_replacement.text).not_to include("Turbo Game")
  end

  it "does not expose or delete another Profile's Game" do
    user = FactoryBot.create(:user)
    FactoryBot.create(:profile, user: user)
    other_game = FactoryBot.create(:game, name: "Other Profile Game")
    sign_in user

    get "/games"
    expect(response.body).not_to include(other_game.name)

    expect do
      delete "/games/#{other_game.id}"
    end.not_to change(Game, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "hides creation at five Games and rejects a sixth through HTML and Turbo" do
    user = FactoryBot.create(:user)
    profile = FactoryBot.create(:profile, user: user)
    5.times { |number| FactoryBot.create(:game, profile: profile, name: "Game #{number}") }
    sign_in user

    get "/games"
    expect(response).to have_http_status(:ok)
    expect(parsed_response.at_css("#games_content").text).not_to include("Create Game")

    [ {}, turbo_stream_headers ].each do |headers|
      expect do
        post "/games", params: { game: { name: "Sixth Game" } }, headers: headers
      end.not_to change(profile.games, :count)

      expect(response).to have_http_status(:unprocessable_content)
      content = headers.empty? ? parsed_response.at_css("#games_content") : turbo_replacement
      expect(content.at_css('[role="alert"]').text).to include("at most 5 games")
    end
  end
end
