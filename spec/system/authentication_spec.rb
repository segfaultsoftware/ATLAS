require "rails_helper"
require_relative "../support/browser_system_testing"

RSpec.describe "Authentication", type: :system, system: true do
  before do
    driven_by :selenium, using: :chrome, screen_size: BrowserSystemTesting::SCREEN_SIZE,
      options: { name: :authentication_headless_chrome } do |options|
      BrowserSystemTesting.configure_chrome_options(options)
    end
  end

  before(:context) do
    BrowserSystemTesting.verify_browser!
  end

  it "renders constrained dark-and-gold login and sign-up forms at the desktop viewport" do
    visit new_user_session_path

    expect(page.driver.browser.manage.window.size.to_a).to eq(BrowserSystemTesting::SCREEN_SIZE)
    expect_authentication_panel("Log in")
    expect_authentication_palette

    find("a.auth-page__link", text: "Sign up", exact_text: true).click

    expect_authentication_panel("Sign up")
    expect_authentication_palette
  end

  it "keeps registration and validation feedback contained at the narrow viewport" do
    page.driver.browser.manage.window.resize_to(640, 720)
    visit new_user_registration_path

    expect(page.evaluate_script("document.documentElement.scrollWidth")).to be <= 640
    expect_element_horizontally_within_viewport(find(".auth-page__panel"))

    fill_in "Email", with: "pilot@example.com"
    fill_in "Password", with: "password123"
    fill_in "Password confirmation", with: "different"
    click_button "Sign up"

    errors = find("#error_explanation.auth-errors[role='alert']")
    panel = find(".auth-page__panel")
    error_rect = element_rect(errors)
    panel_rect = element_rect(panel)

    expect(page.evaluate_script("document.documentElement.scrollWidth")).to be <= 640
    expect_element_horizontally_within_viewport(panel)
    expect(error_rect.fetch("left")).to be >= panel_rect.fetch("left")
    expect(error_rect.fetch("right")).to be <= panel_rect.fetch("right")
    expect(page).to have_css(".auth-errors__list", text: "Password confirmation doesn't match Password")

    error_style = computed_style(errors)
    expect(error_style.fetch("borderLeftWidth").to_f).to be >= 3
    expect_element_vertically_reachable(find("a.auth-page__link", text: "Log in", exact_text: true))
  end

  it "provides visible keyboard focus for every login control type" do
    visit new_user_session_path

    email = find_field("Email")
    password = find_field("Password")
    remember_me = find_field("Remember me")
    submit = find_button("Log in")
    sign_up = find("a.auth-page__link", text: "Sign up", exact_text: true)

    expect_visible_authentication_focus(email)
    email.send_keys(:tab)
    expect_visible_authentication_focus(password)
    password.send_keys(:tab)
    expect_visible_authentication_focus(remember_me)
    remember_me.send_keys(:tab)
    expect_visible_authentication_focus(submit)
    submit.send_keys(:tab)
    expect_visible_authentication_focus(sign_up)
  end

  it "retains native remember-me interaction" do
    user = FactoryBot.create(:user, email: "pilot@example.com", password: "password123", password_confirmation: "password123")

    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    check "Remember me"

    expect(find_field("Remember me")).to be_checked

    click_button "Log in"

    expect(page).to have_current_path(root_path)

    find("summary.account-menu__button[aria-label='Account menu']").click
    within(".account-menu") { click_button "Logout" }

    expect(page).to have_current_path(root_path)
    expect(page).to have_link("Log in", href: new_user_session_path)
  end

  it "exposes failed-login feedback at the narrow viewport" do
    user = FactoryBot.create(:user, email: "pilot@example.com", password: "password123", password_confirmation: "password123")

    page.driver.browser.manage.window.resize_to(640, 720)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "incorrect-password"
    click_button "Log in"

    alert = find(".site-notice.site-notice--alert[role='alert'][aria-live='assertive']")
    expect(alert).to be_visible
    expect_element_within_viewport(alert)
    expect(computed_style(alert).fetch("borderLeftWidth").to_f).to be >= 3
  end

  it "defines deterministic hover, placeholder, autofill, checkbox, and focus contracts" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to match(/\.auth-form__input::placeholder\s*\{[^}]*color:/m)
    expect(stylesheet).to match(/\.auth-form__input:-webkit-autofill:focus\s*\{[^}]*-webkit-text-fill-color:[^}]*box-shadow:/m)
    expect(stylesheet).to match(/\.auth-form__submit:hover\s*\{[^}]*background:/m)
    expect(stylesheet).to match(/\.auth-page__link:hover\s*\{[^}]*color:/m)
    expect(stylesheet).to match(/\.auth-form__checkbox\s*\{[^}]*accent-color:/m)
    expect(stylesheet).to match(/\.auth-page__link:focus-visible\s*\{[^}]*outline:[^}]*outline-offset:/m)
  end

  private

  def expect_authentication_panel(heading)
    expect(page).to have_css(".auth-page__heading", text: heading, exact_text: true)

    panel = find(".auth-page__panel")
    rect = element_rect(panel)
    viewport_width = page.evaluate_script("document.documentElement.clientWidth")

    expect(rect.fetch("width")).to be <= 640
    expect(rect.fetch("left") + (rect.fetch("width") / 2.0)).to be_within(2).of(viewport_width / 2.0)
    expect(rect.fetch("left")).to be >= 0
    expect(rect.fetch("right")).to be <= viewport_width
  end

  def expect_authentication_palette
    label_style = computed_style(find(".auth-form__field label", match: :first))
    input_style = computed_style(find(".auth-form__input", match: :first))
    submit_style = computed_style(find(".auth-form__submit"))

    expect(label_style.fetch("color")).to eq("rgb(229, 184, 91)")
    expect(input_style.fetch("backgroundColor")).to eq("rgb(245, 241, 232)")
    expect(input_style.fetch("color")).to eq("rgb(25, 23, 20)")
    expect(submit_style.fetch("backgroundColor")).to eq("rgb(229, 184, 91)")
    expect(submit_style.fetch("color")).to eq("rgb(25, 23, 20)")
  end

  def expect_visible_authentication_focus(element)
    expect(element).to match_css(":focus")

    style = computed_style(element)
    expect(style.fetch("outlineStyle")).to eq("solid")
    expect(style.fetch("outlineWidth")).to eq("3px")
    expect(style.fetch("outlineColor")).to eq("rgb(245, 210, 132)")
  end

  def expect_element_horizontally_within_viewport(element)
    rect = element_rect(element)
    viewport_width = page.evaluate_script("document.documentElement.clientWidth")

    expect(rect.fetch("left")).to be >= 0
    expect(rect.fetch("right")).to be <= viewport_width
  end

  def expect_element_vertically_reachable(element)
    page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", element)
    rect = element_rect(element)
    viewport_height = page.evaluate_script("document.documentElement.clientHeight")

    expect(rect.fetch("top")).to be >= 0
    expect(rect.fetch("bottom")).to be <= viewport_height
  end

  def expect_element_within_viewport(element)
    expect_element_horizontally_within_viewport(element)

    rect = element_rect(element)
    viewport_height = page.evaluate_script("document.documentElement.clientHeight")
    expect(rect.fetch("top")).to be >= 0
    expect(rect.fetch("bottom")).to be <= viewport_height
  end

  def element_rect(element)
    page.evaluate_script("arguments[0].getBoundingClientRect().toJSON()", element)
  end

  def computed_style(element)
    page.evaluate_script(<<~JAVASCRIPT, element)
      (() => {
        const style = getComputedStyle(arguments[0])
        return {
          backgroundColor: style.backgroundColor,
          borderLeftWidth: style.borderLeftWidth,
          boxShadow: style.boxShadow,
          color: style.color,
          outlineColor: style.outlineColor,
          outlineStyle: style.outlineStyle,
          outlineWidth: style.outlineWidth
        }
      })()
    JAVASCRIPT
  end
end
