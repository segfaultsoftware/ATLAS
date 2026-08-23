require "rails_helper"
require_relative "../support/browser_system_testing"
require "warden/test/helpers"

RSpec.describe "Game initializations", type: :system, system: true do
  include Warden::Test::Helpers

  before do
    driven_by :selenium, using: :chrome, screen_size: BrowserSystemTesting::SCREEN_SIZE,
      options: { name: :game_initializations_headless_chrome } do |options|
      BrowserSystemTesting.configure_chrome_options(options)
    end
  end

  before(:context) do
    BrowserSystemTesting.verify_browser!
  end

  it "renders exactly one editable candidate alongside persisted hired crew" do
    user = FactoryBot.create(:user)
    profile = FactoryBot.create(:profile, user: user)
    game = FactoryBot.create(:game, profile: profile)
    FactoryBot.create(:pawn, game: game, first_name: "Ada", nickname: "Ace")
    login_as user, scope: :user

    visit game_initialization_path(game)

    expect(page).to have_css(".crew-card--hired", count: 1)
    expect(page).to have_css(".crew-card--candidate", count: 1)
    within(".crew-card--candidate") do
      expect(page).to have_field("First Name")
      expect(page).to have_field("Nickname")
      expect(page).to have_field("Last Name")
    end
  end

  it "keeps the name fields constrained, ordered, and linked by a trimmed nickname placeholder" do
    game = create_signed_in_game

    visit game_initialization_path(game)

    first_name = find_field("First Name")
    nickname = find_field("Nickname")
    last_name = find_field("Last Name")
    expect([ first_name[:maxlength], nickname[:maxlength], last_name[:maxlength] ]).to eq([ "18", "18", "18" ])
    expect(first_name[:required]).to eq("true")
    expect(nickname[:required]).to eq("false")
    expect(last_name[:required]).to eq("false")

    first_name.click
    first_name.send_keys(:tab)
    expect(nickname).to match_css(":focus")
    nickname.send_keys(:tab)
    expect(last_name).to match_css(":focus")

    first_name.fill_in(with: "  Grace  ")
    expect(nickname[:placeholder]).to eq("Grace")
  end

  it "previews stat costs and age locally, disables an unaffordable hire, and passes to a fresh candidate" do
    game = create_signed_in_game
    game.game_initialization.update!(remaining_budget: 200)

    visit game_initialization_path(game)

    expect(candidate_output("age")).to have_text("16.00", exact: true)
    expect(candidate_output("healthOutput")).to have_text("100", exact: true)
    expect(page).to have_text("Remaining budget: 200")
    expect(page).to have_css("button[aria-label='Increase maximum Health']")
    expect(page).to have_css("button[aria-label='Increase maximum Stamina']")
    expect(page).to have_css("button[aria-label='Increase maximum Vigor']")

    increase_stat("Health")
    increase_stat("Stamina")
    increase_stat("Vigor")

    expect(candidate_output("age")).to have_text("16.75", exact: true)
    expect(candidate_output("healthOutput")).to have_text("110", exact: true)
    expect(candidate_output("staminaOutput")).to have_text("110", exact: true)
    expect(candidate_output("vigorOutput")).to have_text("110", exact: true)
    expect(page).to have_text("Remaining budget: -100")
    expect(page).to have_button("Hire", disabled: true)
    expect(page).to have_button("Pass", disabled: false)
    expect(page).to have_css(".crew-candidate__stats button", count: 3)

    fill_in "First Name", with: "Ada"
    fill_in "Nickname", with: "Ace"
    fill_in "Last Name", with: "Lovelace"
    click_button "Pass"

    expect(find_field("First Name").value).to eq("")
    expect(find_field("Nickname").value).to eq("")
    expect(find_field("Last Name").value).to eq("")
    expect(candidate_output("age")).to have_text("16.00", exact: true)
    expect(candidate_output("healthOutput")).to have_text("100", exact: true)
    expect(candidate_output("staminaOutput")).to have_text("100", exact: true)
    expect(candidate_output("vigorOutput")).to have_text("100", exact: true)
    expect(page).to have_text("Remaining budget: 200")
    expect(page).to have_button("Hire", disabled: false)
    expect(find_field("First Name")).to match_css(":focus")
  end

  it "hires a candidate, renders it as text, and resets the persisted budget and candidate" do
    game = create_signed_in_game

    visit game_initialization_path(game)
    fill_in "First Name", with: "  Ada  "
    fill_in "Last Name", with: "  Lovelace  "
    increase_stat("Health")
    click_button "Hire"

    expect(page).to have_current_path(game_initialization_path(game))
    expect(page).to have_css(".crew-card--hired", count: 1)
    expect(page).to have_css(".crew-card--candidate", count: 1)
    hired_card = find(".crew-card--hired")
    within(hired_card) do
      expect(page).to have_text("Ada")
      expect(page).to have_text("Lovelace")
      expect(page).to have_no_css("input, button, select, textarea")
    end
    expect(hired_card.text(normalize_ws: true)).to include("Maximum Health 110")
    expect(find_field("First Name").value).to eq("")
    expect(candidate_output("age")).to have_text("16.00", exact: true)
    expect(page).to have_text("Remaining budget: 4900")

    pawn = game.pawns.reload.sole
    expect(pawn).to have_attributes(
      first_name: "Ada",
      nickname: "Ada",
      last_name: "Lovelace",
      born_on_turn: -97_500_000,
      max_health: 110,
      current_health: 110
    )
    expect(game.game_initialization.reload.remaining_budget).to eq(4900)
  end

  it "retains an invalid candidate and local preview without persisting either side of the hire" do
    game = create_signed_in_game

    visit game_initialization_path(game)
    fill_in "First Name", with: "  Retained  "
    fill_in "Nickname", with: "  Candidate  "
    fill_in "Last Name", with: "  State  "
    page.execute_script(<<~JAVASCRIPT)
      const input = document.querySelector("[name='pawn[max_health]']")
      input.value = "105"
    JAVASCRIPT
    click_button "Hire"

    expect(page).to have_css("[role='alert']", text: "Unable to hire candidate")
    expect(page).to have_css(".crew-card--candidate", count: 1)
    expect(page).to have_no_css(".crew-card--hired")
    expect(find_field("First Name").value).to eq("  Retained  ")
    expect(find_field("Nickname").value).to eq("  Candidate  ")
    expect(find_field("Last Name").value).to eq("  State  ")
    expect(candidate_output("healthOutput")).to have_text("105", exact: true)
    expect(candidate_output("age")).to have_text("16.13", exact: true)
    expect(page).to have_text("Remaining budget: 4950")
    expect(game.pawns.reload).to be_empty
    expect(game.game_initialization.reload.remaining_budget).to eq(5000)
  end

  it "supports repeated hires, reloads persisted crew, and stays usable at 640 pixels" do
    game = create_signed_in_game

    visit game_initialization_path(game)
    fill_in "First Name", with: "Ada"
    click_button "Hire"
    expect(page).to have_css(".crew-card--hired", count: 1)
    expect(page).to have_text("Remaining budget: 5000")
    fill_in "First Name", with: "Grace"
    increase_stat("Vigor")
    click_button "Hire"

    expect(page).to have_css(".crew-card--hired", count: 2)
    expect(page).to have_css(".crew-card--candidate", count: 1)
    expect(game.pawns.reload.map(&:first_name)).to eq([ "Ada", "Grace" ])
    expect(game.game_initialization.reload.remaining_budget).to eq(4900)

    refresh
    expect(page).to have_css(".crew-card--hired", count: 2)
    expect(page).to have_css(".crew-card--candidate", count: 1)
    expect(find_field("First Name").value).to eq("")
    expect(page).to have_text("Remaining budget: 4900")

    page.driver.browser.manage.window.resize_to(640, 720)
    first_name = find_field("First Name")
    first_name.click
    first_name.send_keys(:tab, :tab, :tab)
    focused_style = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const style = getComputedStyle(document.activeElement)
        return { outlineStyle: style.outlineStyle, boxShadow: style.boxShadow }
      })()
    JAVASCRIPT
    column_count = page.evaluate_script(
      "getComputedStyle(document.querySelector('.crew-grid')).gridTemplateColumns.split(' ').length"
    )

    expect(page.evaluate_script("document.documentElement.scrollWidth")).to be <= 640
    expect(column_count).to be <= 3
    expect(focused_style.fetch("outlineStyle") != "none" || focused_style.fetch("boxShadow") != "none").to be(true)
  end

  private

  def create_signed_in_game
    page.reset_session!
    user = FactoryBot.create(:user)
    profile = FactoryBot.create(:profile, user: user)
    game = FactoryBot.create(:game, profile: profile)
    login_as user, scope: :user

    game
  end

  def candidate_output(target)
    find("[data-crew-candidate-target='#{target}']")
  end

  def increase_stat(stat)
    find("button[aria-label='Increase maximum #{stat}']").click
  end
end
