require "rails_helper"

RSpec.describe ManualPage, type: :model do
  it "stores Markdown pages with stable slugs" do
    page = FactoryBot.create(
      :manual_page,
      title: "Getting Started",
      slug: "getting-started",
      content: "# Getting Started"
    )

    expect(page.reload.attributes).to include(
      "title" => "Getting Started",
      "slug" => "getting-started",
      "content" => "# Getting Started"
    )
  end

  it "requires unique slugs" do
    FactoryBot.create(:manual_page, slug: "getting-started")
    duplicate = FactoryBot.build(:manual_page, slug: "getting-started")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors.of_kind?(:slug, :taken)).to be(true)
  end

  it "supports parent and child page relationships" do
    parent = FactoryBot.create(:manual_page, slug: "getting-started")
    child = FactoryBot.create(:manual_page, slug: "first-steps", parent: parent)

    expect(child.parent).to eq(parent)
    expect(parent.children).to contain_exactly(child)
  end

  it "rejects cyclic parent relationships" do
    parent = FactoryBot.create(:manual_page, slug: "parent")
    child = FactoryBot.create(:manual_page, slug: "child", parent: parent)

    parent.parent = child

    expect(parent).not_to be_valid
    expect(parent.errors[:parent]).to include("cannot create a cycle")
  end

  it "returns ancestors from the root toward the page" do
    grandparent = FactoryBot.create(:manual_page, slug: "grandparent")
    parent = FactoryBot.create(:manual_page, slug: "parent", parent: grandparent)
    page = FactoryBot.create(:manual_page, slug: "page", parent: parent)

    expect(page.ancestors).to eq([ grandparent, parent ])
  end

  it "associates pages with categories" do
    page = FactoryBot.create(:manual_page)
    category = FactoryBot.create(:manual_category)

    page.categories << category

    expect(page.categories).to contain_exactly(category)
    expect(category.manual_pages).to contain_exactly(page)
  end
end
