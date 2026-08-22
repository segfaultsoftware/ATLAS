require "rails_helper"

RSpec.describe Pawn, type: :model do
  let(:stat_attributes) do
    %i[
      max_health
      current_health
      max_stamina
      current_stamina
      max_vigor
      current_vigor
    ]
  end

  describe "associations" do
    it "belongs to a game that exposes it through the inverse association" do
      pawn = FactoryBot.create(:pawn)

      expect(pawn.game.pawns).to include(pawn)
    end
  end

  describe "names" do
    it "trims all names and defaults a blank nickname to the trimmed first name" do
      pawn = FactoryBot.create(
        :pawn,
        first_name: "  Ada  ",
        nickname: " \t ",
        last_name: "  Lovelace  "
      )

      expect(pawn.attributes.slice("first_name", "nickname", "last_name")).to eq(
        "first_name" => "Ada",
        "nickname" => "Ada",
        "last_name" => "Lovelace"
      )
    end

    it "allows an empty trimmed last name" do
      pawn = FactoryBot.create(:pawn, last_name: "   ")

      expect(pawn.last_name).to eq("")
    end

    it "requires a first name and limits every name to 18 characters after trimming" do
      expect(FactoryBot.build(:pawn, first_name: " ")).not_to be_valid

      %i[first_name nickname last_name].each do |attribute|
        expect(FactoryBot.build(:pawn, attribute => "x" * 18)).to be_valid
        expect(FactoryBot.build(:pawn, attribute => "x" * 19)).not_to be_valid
      end
    end
  end

  describe "required numeric attributes" do
    it "requires an integer birth turn" do
      expect(FactoryBot.build(:pawn, born_on_turn: -96_000_000)).to be_valid

      [ nil, 0.5 ].each do |born_on_turn|
        expect(FactoryBot.build(:pawn, born_on_turn: born_on_turn)).not_to be_valid
      end
    end

    it "requires every health, stamina, and vigor value to be a positive integer" do
      stat_attributes.each do |attribute|
        expect(FactoryBot.build(:pawn, attribute => 1)).to be_valid

        [ nil, 0, -1, 0.5 ].each do |value|
          expect(FactoryBot.build(:pawn, attribute => value)).not_to be_valid
        end
      end
    end
  end

  describe "database constraints" do
    let(:pawn) { FactoryBot.create(:pawn) }

    it "rejects null, untrimmed, empty required, and overlong names" do
      ascii_boundary_whitespace = [ " ", "\t", "\n", "\v", "\f", "\r" ]

      {
        first_name: [ nil, "", *ascii_boundary_whitespace.map { |space| "#{space}Ada#{space}" }, "x" * 19 ],
        nickname: [ nil, "", *ascii_boundary_whitespace.map { |space| "#{space}Ace#{space}" }, "x" * 19 ],
        last_name: [ *ascii_boundary_whitespace.map { |space| "#{space}Lovelace#{space}" }, "x" * 19 ]
      }.each do |attribute, invalid_values|
        invalid_values.each do |value|
          expect do
            described_class.where(id: pawn.id).update_all(attribute => value)
          end.to raise_error(ActiveRecord::StatementInvalid)
        end
      end
    end

    it "allows an empty or null last name" do
      expect do
        described_class.where(id: pawn.id).update_all(last_name: "")
        described_class.where(id: pawn.id).update_all(last_name: nil)
      end.not_to raise_error
    end

    it "rejects null birth turns and nonpositive or null stats" do
      expect do
        described_class.where(id: pawn.id).update_all(born_on_turn: nil)
      end.to raise_error(ActiveRecord::StatementInvalid)

      stat_attributes.each do |attribute|
        [ nil, 0, -1 ].each do |value|
          expect do
            described_class.where(id: pawn.id).update_all(attribute => value)
          end.to raise_error(ActiveRecord::StatementInvalid)
        end
      end
    end

    it "rejects an absent game" do
      expect do
        described_class.where(id: pawn.id).update_all(game_id: -1)
      end.to raise_error(ActiveRecord::StatementInvalid)
    end
  end
end
