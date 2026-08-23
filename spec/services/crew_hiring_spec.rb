require "rails_helper"

RSpec.describe "CrewHiring", type: :service do
  def valid_candidate_attributes(overrides = {})
    {
      first_name: "Ada",
      nickname: "Ace",
      last_name: "Lovelace",
      max_health: 120,
      max_stamina: 130,
      max_vigor: 110,
      starting_budget: 5000
    }.merge(overrides)
  end

  it "persists a valid Pawn with server-derived values and reduces the current budget by its derived cost" do
    game = FactoryBot.create(:game)
    pawn = nil

    expect do
      pawn = CrewHiring.call(
        game: game,
        candidate_attributes: valid_candidate_attributes
      )
    end.to change(Pawn, :count).by(1)

    expect(pawn).to be_persisted
    expect(pawn).to have_attributes(
      game: game,
      first_name: "Ada",
      nickname: "Ace",
      last_name: "Lovelace",
      born_on_turn: -105_000_000,
      max_health: 120,
      current_health: 120,
      max_stamina: 130,
      current_stamina: 130,
      max_vigor: 110,
      current_vigor: 110
    )
    expect(game.game_initialization.reload.remaining_budget).to eq(4400)
  end

  it "normalizes names, applies the nickname fallback, and ignores forged derived values" do
    game = FactoryBot.create(:game)

    pawn = CrewHiring.call(
      game: game,
      candidate_attributes: valid_candidate_attributes(
        first_name: "  Ada  ",
        nickname: "  ",
        last_name: "  Lovelace  ",
        max_health: "110",
        max_stamina: "100",
        max_vigor: "100",
        starting_budget: "5000",
        age: 99,
        born_on_turn: -1,
        current_health: 1,
        current_stamina: 1,
        current_vigor: 1,
        cost: 0,
        remaining_budget: 5000
      )
    )

    expect(pawn).to have_attributes(
      first_name: "Ada",
      nickname: "Ada",
      last_name: "Lovelace",
      born_on_turn: -97_500_000,
      max_health: 110,
      current_health: 110,
      max_stamina: 100,
      current_stamina: 100,
      max_vigor: 100,
      current_vigor: 100
    )
    expect(game.game_initialization.reload.remaining_budget).to eq(4900)
  end

  it "rejects missing or overlong names without changing either record" do
    game = FactoryBot.create(:game)

    [ "  ", "x" * 19 ].each do |first_name|
      pawn = nil

      expect do
        pawn = CrewHiring.call(
          game: game,
          candidate_attributes: valid_candidate_attributes(first_name: first_name)
        )
      end.not_to change(Pawn, :count)

      expect(pawn.errors[:first_name]).to be_present
      expect(game.game_initialization.reload.remaining_budget).to eq(5000)
    end
  end

  it "rejects every malformed maximum-stat class without changing either record" do
    game = FactoryBot.create(:game)

    [ nil, "100.0", "one hundred", 99, 105 ].each do |invalid_value|
      %i[max_health max_stamina max_vigor].each do |attribute|
        pawn = nil

        expect do
          pawn = CrewHiring.call(
            game: game,
            candidate_attributes: valid_candidate_attributes(attribute => invalid_value)
          )
        end.not_to change(Pawn, :count)

        expect(pawn.errors[attribute]).to be_present
        expect(game.game_initialization.reload.remaining_budget).to eq(5000)
      end
    end
  end

  it "rejects malformed, stale, and insufficient starting budgets" do
    game = FactoryBot.create(:game)

    [ nil, "5000.0", 4900 ].each do |starting_budget|
      pawn = CrewHiring.call(
        game: game,
        candidate_attributes: valid_candidate_attributes(starting_budget: starting_budget)
      )

      expect(pawn).not_to be_persisted
      expect(pawn.errors[:starting_budget]).to be_present
    end

    expect(game.pawns.reload).to be_empty
    expect(game.game_initialization.reload.remaining_budget).to eq(5000)

    game.game_initialization.update!(remaining_budget: 500)
    pawn = CrewHiring.call(
      game: game,
      candidate_attributes: valid_candidate_attributes(starting_budget: 500)
    )

    expect(pawn).not_to be_persisted
    expect(pawn.errors.full_messages).to include("Remaining budget cannot be negative")
    expect(game.game_initialization.reload.remaining_budget).to eq(500)
  end

  it "rejects a Game without an initialization" do
    game = FactoryBot.create(:game)
    game.game_initialization.destroy!

    pawn = CrewHiring.call(game: game, candidate_attributes: valid_candidate_attributes)

    expect(pawn).not_to be_persisted
    expect(pawn.errors.full_messages).to include("Game initialization is required")
  end

  it "leaves the budget unchanged when Pawn persistence fails" do
    game = FactoryBot.create(:game)
    allow_any_instance_of(Pawn).to receive(:save!).and_raise(ActiveRecord::RecordNotSaved, "Pawn failed")

    pawn = CrewHiring.call(game: game, candidate_attributes: valid_candidate_attributes)

    expect(pawn).not_to be_persisted
    expect(pawn.errors).to be_present
    expect(game.game_initialization.reload.remaining_budget).to eq(5000)
  end

  it "rolls back the Pawn when budget persistence fails" do
    game = FactoryBot.create(:game)
    allow_any_instance_of(GameInitialization)
      .to receive(:update!)
      .and_raise(ActiveRecord::RecordNotSaved, "Budget failed")

    expect do
      pawn = CrewHiring.call(game: game, candidate_attributes: valid_candidate_attributes)
      expect(pawn).not_to be_persisted
      expect(pawn.errors).to be_present
    end.not_to change(Pawn, :count)

    expect(game.game_initialization.reload.remaining_budget).to eq(5000)
  end

  context "with competing database connections" do
    self.use_transactional_tests = false

    let(:user_email) { "crew-hiring-concurrency@example.com" }

    after do
      User.find_by(email: user_email)&.destroy!
    end

    it "serializes competing hires so one succeeds and one rejects its stale snapshot" do
      profile = FactoryBot.create(:profile, user: FactoryBot.create(:user, email: user_email))
      game = FactoryBot.create(:game, profile: profile)
      game.game_initialization.update!(remaining_budget: 100)
      first_reached_pawn_write = Queue.new
      release_first_transaction = Queue.new
      second_connection_ready = Queue.new
      start_second_attempt = Queue.new
      second_begin_attempted = Queue.new
      second_result = Queue.new

      allow_any_instance_of(Pawn).to receive(:save!).and_wrap_original do |save, **arguments|
        if save.receiver.first_name == "First"
          first_reached_pawn_write << true
          release_first_transaction.pop
        end
        save.call(**arguments)
      end

      first_attempt = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          pawn = CrewHiring.call(
            game: Game.find(game.id),
            candidate_attributes: valid_candidate_attributes(
              first_name: "First",
              max_health: 110,
              max_stamina: 100,
              max_vigor: 100,
              starting_budget: 100
            )
          )
          { connection_id: connection.object_id, pawn: pawn }
        rescue StandardError => error
          { connection_id: connection.object_id, error: error }
        end
      end

      first_reached_pawn_write.pop(timeout: 2)
      second_attempt = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          second_connection_ready << connection
          start_second_attempt.pop
          pawn = CrewHiring.call(
            game: Game.find(game.id),
            candidate_attributes: valid_candidate_attributes(
              first_name: "Second",
              max_health: 110,
              max_stamina: 100,
              max_vigor: 100,
              starting_budget: 100
            )
          )
          second_result << { connection_id: connection.object_id, pawn: pawn }
        rescue StandardError => error
          second_result << { connection_id: connection.object_id, error: error }
        end
      end

      second_connection = second_connection_ready.pop(timeout: 2)
      allow(second_connection).to receive(:begin_db_transaction).and_wrap_original do |begin_transaction|
        second_begin_attempted << true
        begin_transaction.call
      end
      start_second_attempt << true
      second_begin_attempted.pop(timeout: 2)
      release_first_transaction << true

      results = [ first_attempt.value, second_result.pop(timeout: 2) ]
      second_attempt.join

      expect(results.pluck(:connection_id).uniq.size).to eq(2)
      expect(results).not_to include(include(:error))
      expect(results.count { |result| result.fetch(:pawn).persisted? }).to eq(1)
      rejected = results.find { |result| !result.fetch(:pawn).persisted? }.fetch(:pawn)
      expect(rejected.errors[:starting_budget]).to be_present
      expect(game.pawns.reload.size).to eq(1)
      expect(game.game_initialization.reload.remaining_budget).to eq(0)
      expect(ActiveRecord::Base.connection_db_config.configuration_hash.fetch(:timeout)).to eq(5000)
    end
  end
end
