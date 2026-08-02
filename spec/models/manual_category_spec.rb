require "rails_helper"

RSpec.describe ManualCategory, type: :model do
  it "requires a unique slug" do
    FactoryBot.create(:manual_category, slug: "navigation")
    duplicate = FactoryBot.build(:manual_category, slug: "navigation")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors.of_kind?(:slug, :taken)).to be(true)
  end
end
