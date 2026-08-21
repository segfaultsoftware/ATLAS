require "rails_helper"

RSpec.describe Game, type: :model do
  describe "associations" do
    it "belongs to a profile" do
      game = FactoryBot.build(:game)

      expect(game.profile).to be_a(Profile)
      expect(game).to be_valid
      expect(game.randomization_seed).to be_between(0, 4_294_967_295)
    end

    it "owns one initialization and many Pawns that are deleted with it" do
      game = FactoryBot.create(:game)
      initialization = game.game_initialization
      pawn = FactoryBot.create(:pawn, game: game)

      expect(initialization).to be_persisted
      expect(game.pawns).to contain_exactly(pawn)

      expect do
        game.destroy!
      end.to change(GameInitialization, :count).by(-1)
        .and change(Pawn, :count).by(-1)
    end

    it "cascades initialization and Pawn deletion at the database boundary" do
      game = FactoryBot.create(:game)
      initialization = game.game_initialization
      pawn = FactoryBot.create(:pawn, game: game)

      Game.where(id: game.id).delete_all

      expect(GameInitialization.exists?(initialization.id)).to be(false)
      expect(Pawn.exists?(pawn.id)).to be(false)
    end
  end

  describe "name" do
    it "trims the name before validation and persistence" do
      game = FactoryBot.create(:game, name: "  Voyager  ")

      expect(game.reload.name).to eq("Voyager")
    end

    it "requires between 1 and 64 characters after trimming" do
      expect(FactoryBot.build(:game, name: " x ")).to be_valid
      expect(FactoryBot.build(:game, name: "x" * 64)).to be_valid

      blank_game = FactoryBot.build(:game, name: " \t ")
      long_game = FactoryBot.build(:game, name: "x" * 65)

      expect(blank_game).not_to be_valid
      expect(blank_game.errors.of_kind?(:name, :blank)).to be(true)
      expect(long_game).not_to be_valid
      expect(long_game.errors.of_kind?(:name, :too_long)).to be(true)
    end

    it "allows duplicate names within one profile" do
      profile = FactoryBot.create(:profile)

      first_game = FactoryBot.create(:game, profile: profile, name: "Voyager")
      second_game = FactoryBot.create(:game, profile: profile, name: "Voyager")

      expect(first_game.name).to eq(second_game.name)
    end
  end

  describe "randomization seed" do
    it "replaces caller input with one system-generated unsigned 32-bit value on creation" do
      allow(SecureRandom).to receive(:random_number).with(2**32).and_return(4_000_000_000)

      game = FactoryBot.build(:game, randomization_seed: 7)
      game.valid?
      game.valid?
      game.save!

      expect(game.randomization_seed).to eq(4_000_000_000)
      expect(SecureRandom).to have_received(:random_number).with(2**32).once
    end

    it "allows duplicate generated seeds" do
      profile = FactoryBot.create(:profile)
      allow(SecureRandom).to receive(:random_number).with(2**32).and_return(123)

      first_game = FactoryBot.create(:game, profile: profile)
      second_game = FactoryBot.create(:game, profile: profile)

      expect(first_game.randomization_seed).to eq(123)
      expect(second_game.randomization_seed).to eq(123)
    end

    it "raises on ordinary assignment after persistence without changing the stored seed" do
      game = FactoryBot.create(:game)
      original_seed = game.randomization_seed

      expect do
        game.randomization_seed = original_seed ^ 1
      end.to raise_error(ActiveRecord::ReadonlyAttributeError)
      expect(game.reload.randomization_seed).to eq(original_seed)
    end
  end

  describe "database constraints" do
    let(:profile) { FactoryBot.create(:profile) }
    let(:timestamp) { Time.current }

    def insert_game!(profile_id:, name:, randomization_seed:)
      described_class.insert_all!([ {
        profile_id: profile_id,
        name: name,
        randomization_seed: randomization_seed,
        created_at: timestamp,
        updated_at: timestamp
      } ])
    end

    it "accepts both unsigned 32-bit seed boundaries" do
      expect do
        insert_game!(profile_id: profile.id, name: "Minimum", randomization_seed: 0)
        insert_game!(profile_id: profile.id, name: "Maximum", randomization_seed: 4_294_967_295)
      end.to change(described_class, :count).by(2)
    end

    it "rejects null and out-of-range seeds" do
      [ nil, -1, 4_294_967_296 ].each do |seed|
        expect do
          insert_game!(profile_id: profile.id, name: "Invalid seed", randomization_seed: seed)
        end.to raise_error(ActiveRecord::StatementInvalid)
      end
    end

    it "rejects names that are null, empty, overlong, or not trimmed" do
      [ nil, "", "   ", "x" * 65, " Voyager " ].each do |name|
        expect do
          insert_game!(profile_id: profile.id, name: name, randomization_seed: 123)
        end.to raise_error(ActiveRecord::StatementInvalid)
      end
    end

    it "rejects an absent profile" do
      expect do
        insert_game!(profile_id: -1, name: "Orphan", randomization_seed: 123)
      end.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe "profile capacity" do
    it "allows five games and rejects a sixth through direct model usage" do
      profile = FactoryBot.create(:profile)
      5.times { |number| FactoryBot.create(:game, profile: profile, name: "Game #{number}") }

      sixth_game = FactoryBot.build(:game, profile: profile, name: "Game 6")

      expect(sixth_game.save).to be(false)
      expect(sixth_game.errors[:base]).to be_present
      expect(profile.games.reload.size).to eq(5)
    end

    context "with competing database connections" do
      self.use_transactional_tests = false

      let(:user_email) { "game-capacity-concurrency@example.com" }

      after do
        User.find_by(email: user_email)&.destroy!
      end

      it "serializes competing fifth and sixth creations into one success and one controlled failure" do
        profile = FactoryBot.create(:profile, user: FactoryBot.create(:user, email: user_email))
        4.times { |number| FactoryBot.create(:game, profile: profile, name: "Existing #{number}") }
        fifth_game = FactoryBot.build(:game, profile: profile, name: "Fifth")
        sixth_game = FactoryBot.build(:game, profile: profile, name: "Sixth")
        fifth_capacity_checked = Queue.new
        release_fifth_transaction = Queue.new
        sixth_connection_ready = Queue.new
        start_sixth_attempt = Queue.new
        sixth_begin_attempted = Queue.new
        sixth_result = Queue.new

        allow(fifth_game).to receive(:profile_has_capacity).and_wrap_original do |capacity_check|
          capacity_check.call
          fifth_capacity_checked << true
          release_fifth_transaction.pop
        end

        fifth_attempt = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            { connection_id: connection.object_id, saved: fifth_game.save, errors: fifth_game.errors[:base] }
          rescue StandardError => error
            { connection_id: connection.object_id, error: error }
          end
        end

        fifth_capacity_checked.pop(timeout: 2)
        sixth_attempt = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            sixth_connection_ready << connection
            start_sixth_attempt.pop
            sixth_result << {
              connection_id: connection.object_id,
              saved: sixth_game.save,
              errors: sixth_game.errors[:base]
            }
          rescue StandardError => error
            sixth_result << { connection_id: connection.object_id, error: error }
          end
        end

        sixth_connection = sixth_connection_ready.pop(timeout: 2)
        allow(sixth_connection).to receive(:begin_db_transaction).and_wrap_original do |begin_transaction|
          sixth_begin_attempted << true
          begin_transaction.call
        end
        start_sixth_attempt << true
        sixth_begin_attempted.pop(timeout: 2)

        begin
          early_sixth_result = sixth_result.pop(timeout: 0.05)
        ensure
          release_fifth_transaction << true
        end

        expect(early_sixth_result).to be_nil

        results = [ fifth_attempt.value, sixth_result.pop(timeout: 2) ]
        sixth_attempt.join

        expect(results.pluck(:connection_id).uniq.size).to eq(2)
        expect(results).not_to include(include(:error))
        expect(results.count { |result| result[:saved] }).to eq(1)
        expect(results.find { |result| !result[:saved] }.fetch(:errors)).to be_present
        expect(profile.games.reload.size).to eq(5)
        expect(ActiveRecord::Base.connection_db_config.configuration_hash.fetch(:timeout)).to eq(5000)
      end
    end
  end
end
