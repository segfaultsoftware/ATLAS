require "rails_helper"

RSpec.describe CelestialBody, type: :model do
  describe "associations" do
    it "retrieves its associated celestial transit" do
      body = FactoryBot.create(:celestial_body)
      transit = FactoryBot.create(:celestial_transit, celestial_body: body)

      expect(body.reload.celestial_transit).to eq(transit)
    end
  end

  describe "validations" do
    it "requires a name" do
      body = FactoryBot.build(:celestial_body, name: nil)

      expect(body).not_to be_valid
      expect(body.errors[:name]).to include("can't be blank")
    end

    it "requires a unique name" do
      body = FactoryBot.create(:celestial_body, name: "Named Body")
      duplicate = FactoryBot.build(:celestial_body, name: body.name)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include("has already been taken")
    end
  end
end
