require "rails_helper"

RSpec.describe "GameInitialization", type: :model do
  describe "associations" do
    it "belongs to a Game that exposes it as the inverse association" do
      initialization = FactoryBot.create(:game).game_initialization

      expect(initialization.game.game_initialization).to eq(initialization)
    end
  end

  describe "remaining budget" do
    it "defaults to 5000" do
      initialization = FactoryBot.create(:game).game_initialization

      expect(initialization.remaining_budget).to eq(5000)
    end

    it "requires a nonnegative integer through the model" do
      expect(FactoryBot.build(:game_initialization, remaining_budget: 0)).to be_valid
      expect(FactoryBot.build(:game_initialization, remaining_budget: 1)).to be_valid

      [ nil, -1, 0.5 ].each do |remaining_budget|
        initialization = FactoryBot.build(:game_initialization, remaining_budget: remaining_budget)

        expect(initialization).not_to be_valid
        expect(initialization.errors[:remaining_budget]).to be_present
      end
    end
  end

  describe "database constraints" do
    let(:game) do
      FactoryBot.create(:game).tap do |created_game|
        created_game.game_initialization.destroy!
      end
    end
    let(:timestamp) { Time.current }

    def insert_initialization!(game_id:, attributes: {})
      GameInitialization.insert_all!([ {
        game_id: game_id,
        created_at: timestamp,
        updated_at: timestamp,
        **attributes
      } ])
    end

    it "applies the default when remaining_budget is omitted" do
      insert_initialization!(game_id: game.id)

      expect(GameInitialization.find_by!(game: game).remaining_budget).to eq(5000)
    end

    it "rejects null and negative remaining budgets" do
      [ nil, -1 ].each do |remaining_budget|
        expect do
          insert_initialization!(game_id: game.id, attributes: { remaining_budget: remaining_budget })
        end.to raise_error(ActiveRecord::StatementInvalid)
      end
    end

    it "rejects a second initialization for one Game and an absent Game" do
      GameInitialization.create!(game: game)

      expect do
        insert_initialization!(game_id: game.id)
      end.to raise_error(ActiveRecord::RecordNotUnique)

      expect do
        insert_initialization!(game_id: -1)
      end.to raise_error(ActiveRecord::StatementInvalid)
    end
  end
end
