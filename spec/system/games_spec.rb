require "rails_helper"
require_relative "../support/browser_system_testing"
require "warden/test/helpers"

RSpec.describe "Games", type: :system, system: true do
  include Warden::Test::Helpers

  before do
    driven_by :selenium, using: :chrome, screen_size: BrowserSystemTesting::SCREEN_SIZE,
      options: { name: :games_headless_chrome } do |options|
      BrowserSystemTesting.configure_chrome_options(options)
    end
  end

  before(:context) do
    BrowserSystemTesting.verify_browser!
  end

  it "renders valid Game controls and navigates initialized Games" do
    profile = create_signed_in_profile
    allow(SecureRandom).to receive(:random_number).with(2**32).and_return(42)
    game = FactoryBot.create(:game, profile: profile, name: "Far Horizon")
    pawn = FactoryBot.create(:pawn, game: game, first_name: "Ada", nickname: "Ace")

    visit games_path

    card = find("article.game-card", text: game.name)
    expect(card).to have_css("a.game-card__load[aria-label='Load Far Horizon']")
    expect(card).to have_css(".game-card__seed", text: "0x0000002A", exact_text: true)
    expect(card).to have_button("Delete Far Horizon")
    expect(card).to have_no_css("a a, a button, button a, button button")

    find("a.game-card__load[aria-label='Load Far Horizon']").click

    expect(page).to have_current_path(game_initialization_path(game))
    expect(page).to have_css("h1", text: "Select Your Crew", exact_text: true)
    hired_card = find(".crew-card--hired", text: pawn.first_name)
    expect(hired_card).to have_text(pawn.nickname)
    expect(hired_card).to have_no_css("input, button, select, textarea")
    column_count = page.evaluate_script(
      "getComputedStyle(document.querySelector('.crew-grid')).gridTemplateColumns.split(' ').length"
    )
    expect(column_count).to be <= 3

    page.driver.browser.manage.window.resize_to(640, 720)
    expect(page.evaluate_script("document.documentElement.scrollWidth")).to be <= 640
  end

  it "opens and focuses creation, submits with Enter, and navigates with a success notice" do
    profile = create_signed_in_profile

    visit games_path

    expect(page).to have_no_field("Name", visible: true)
    click_button "Create Game", match: :first

    name_input = find_field("Name")
    submit_button = find('input[type="submit"][aria-label="Create Game"]')
    input_rect = page.evaluate_script("arguments[0].getBoundingClientRect().toJSON()", name_input)
    submit_rect = page.evaluate_script("arguments[0].getBoundingClientRect().toJSON()", submit_button)

    expect(submit_button.value).to eq("↵")
    expect(submit_rect.fetch("left")).to be >= input_rect.fetch("right")
    expect(submit_rect.fetch("top")).to be_within(1).of(input_rect.fetch("top"))
    expect(submit_rect.fetch("bottom")).to be_within(1).of(input_rect.fetch("bottom"))
    expect(name_input).to match_css(":focus")
    name_input.fill_in(with: "  New Voyage  ")
    name_input.send_keys(:enter)

    expect(page).to have_current_path(%r{/games/\d+/initialization})
    expect(page).to have_css("h1", text: "Select Your Crew", exact_text: true)
    expect(page).to have_css("[role='status'][aria-live='polite']", text: "New Voyage")
    game = profile.games.reload.find_by!(name: "New Voyage")
    expect(page).to have_current_path(game_initialization_path(game))
  end

  it "keeps failed creation open with the entered name and an inline alert" do
    create_signed_in_profile
    invalid_name = "x" * 65

    visit games_path
    click_button "Create Game", match: :first
    page.execute_script("document.querySelector('[name=\"game[name]\"]').removeAttribute('maxlength')")
    fill_in "Name", with: invalid_name
    find_field("Name").send_keys(:enter)

    expect(page).to have_field("Name", with: invalid_name)
    expect(page).to have_css("[role='alert']", text: "Name must contain 1–64 characters after trimming.")
    expect(find_field("Name")).to be_visible
  end

  it "rejects a whitespace-only name in place with an inline frontend error" do
    profile = create_signed_in_profile

    visit games_path
    click_button "Create Game", match: :first
    fill_in "Name", with: "   "
    find_field("Name").send_keys(:enter)

    expect(page).to have_field("Name", with: "   ")
    expect(page).to have_css("[role='alert']", text: "Name must contain 1–64 characters after trimming.")
    expect(profile.games.reload).to be_empty
  end

  it "counts supplementary Unicode characters consistently with backend validation" do
    profile = create_signed_in_profile
    name = "🚀" * 64

    visit games_path
    click_button "Create Game", match: :first
    fill_in "Name", with: "  #{name}  "
    find_field("Name").send_keys(:enter)

    expect(page).to have_current_path(%r{/games/\d+/initialization})
    expect(page).to have_css("h1", text: "Select Your Crew", exact_text: true)
    game = profile.games.reload.sole
    expect(game.name).to eq(name)
    expect(page).to have_current_path(game_initialization_path(game))
  end

  it "cancels deletion without loading and restores focus to the trash control" do
    profile = create_signed_in_profile
    game = FactoryBot.create(:game, profile: profile, name: "Keep Me")

    visit games_path
    delete_button = find_button("Delete Keep Me")
    delete_button.click

    expect(page).to have_css("[role='dialog'][aria-modal='true']")
    expect(page).to have_text("Delete Keep Me?")
    expect(page).to have_no_css("[role='status']", text: "Loading Keep Me...")
    click_button "Cancel"

    expect(page).to have_css("article.game-card", text: game.name)
    expect(page).to have_no_css("[role='dialog']")
    expect(page.evaluate_script("document.activeElement.getAttribute('aria-label')")).to eq("Delete Keep Me")
    expect(profile.games.reload).to include(game)
  end

  it "confirms deletion without loading or refreshing the browser" do
    profile = create_signed_in_profile
    game = FactoryBot.create(:game, profile: profile, name: "Retire Me")

    visit games_path
    mark_document
    find_button("Delete Retire Me").click
    within("[role='dialog']") { click_button "Delete" }

    expect(page).to have_no_css("article.game-card", text: game.name)
    expect(page).to have_no_css("[role='status']", text: "Loading Retire Me...")
    expect(document_mark).to eq("games-system-spec")
    expect(profile.games.reload).not_to include(game)
  end

  it "supports keyboard load and dialog activation without event overlap" do
    profile = create_signed_in_profile
    game = FactoryBot.create(:game, profile: profile, name: "Keyboard Voyage")

    visit games_path
    find("a.game-card__load").send_keys(:enter)
    expect(page).to have_current_path(game_initialization_path(game))

    visit games_path
    find_button("Delete Keyboard Voyage").send_keys(:enter)
    expect(page).to have_css("[role='dialog'][aria-modal='true']")
    expect(page).to have_css("[role='dialog'] button:focus")
    click_button "Cancel"
    expect(profile.games.reload).to include(game)
  end

  it "hides creation at capacity and restores it after a Turbo deletion" do
    profile = create_signed_in_profile
    games = 5.times.map do |number|
      FactoryBot.create(:game, profile: profile, name: "Voyage #{number + 1}")
    end

    visit games_path
    mark_document

    expect(page).to have_no_button("Create Game")
    find_button("Delete #{games.last.name}").click
    within("[role='dialog']") { click_button "Delete" }

    expect(page).to have_button("Create Game")
    expect(document_mark).to eq("games-system-spec")
  end

  it "keeps controls usable with visible keyboard focus at a narrow viewport" do
    profile = create_signed_in_profile
    FactoryBot.create(:game, profile: profile, name: "Narrow Voyage")

    visit games_path
    page.driver.browser.manage.window.resize_to(640, 720)

    load_button = find("a.game-card__load")
    load_button.send_keys(:tab)
    focused_style = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const style = getComputedStyle(document.activeElement)
        return { outlineStyle: style.outlineStyle, outlineWidth: style.outlineWidth, boxShadow: style.boxShadow }
      })()
    JAVASCRIPT

    expect(page.evaluate_script("document.documentElement.scrollWidth")).to be <= 640
    expect(focused_style.fetch("outlineStyle") != "none" || focused_style.fetch("boxShadow") != "none").to be(true)
    expect(focused_style.fetch("outlineWidth")).not_to eq("0px") if focused_style.fetch("outlineStyle") != "none"
  end

  private

  def create_signed_in_profile
    page.reset_session!
    user = FactoryBot.create(:user)
    profile = FactoryBot.create(:profile, user: user)
    login_as user, scope: :user

    profile
  end

  def mark_document
    page.execute_script("window.gamesSystemSpecDocumentMark = 'games-system-spec'")
  end

  def document_mark
    page.evaluate_script("window.gamesSystemSpecDocumentMark")
  end
end
