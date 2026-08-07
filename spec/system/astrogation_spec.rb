require "rails_helper"
require_relative "../support/system_testing"

RSpec.describe "Astrogation", type: :system, system: true do
  before do
    driven_by :selenium, using: :chrome, screen_size: AstrogationSystemTesting::SCREEN_SIZE,
      options: { name: :astrogation_headless_chrome } do |options|
      AstrogationSystemTesting.configure_chrome_options(options)
    end
  end

  before(:context) do
    AstrogationSystemTesting.verify_browser!
  end

  it "loads publicly with the shared header and ship-centered visibility" do
    visit "/astrogation"

    expect(page).to have_css("body > header.site-header")
    expect(page).to have_css("#astrogation-system[data-astrogation-system]")
    expect(page).to have_css(".astrogation-star[data-astrogation-star][data-star-class='M']")
    expect(page).to have_css(".astrogation-star__core[cx='0'][cy='0'][r='0.7']")
    expect(page).to have_css("[data-astrogation-star-description][data-star-class='M']", visible: :all)
    expect(page).to have_css("[data-astrogation-label='Ship']")
    expect(page).to have_css("[data-astrogation-label='Tejat C']")
    expect(page.evaluate_script("document.querySelector('#astrogation-system').dataset.astrogationCenterX").to_f)
      .to be_within(0.001).of(page.evaluate_script("document.querySelector('#astrogation-system').dataset.astrogationShipX").to_f)
  end

  it "supports zoom, pointer pan, recentering, and screen-sized labels" do
    visit "/astrogation"
    viewport = page.find(".astrogation-scene__viewport")
    label_height = page.evaluate_script("document.querySelector('[data-astrogation-label=\"Ship\"] text').getBoundingClientRect().height")
    initial_scale = page.evaluate_script("document.querySelector('#astrogation-system').dataset.astrogationScale").to_f

    page.find("button[aria-label='Zoom in']").click

    expect(page.evaluate_script("document.querySelector('#astrogation-system').dataset.astrogationScale").to_f)
      .to be > initial_scale
    expect(page.evaluate_script("document.querySelector('[data-astrogation-label=\"Ship\"] text').getBoundingClientRect().height"))
      .to be_within(0.5).of(label_height)

    page.driver.browser.action.move_to(viewport.native).click_and_hold.move_by(80, 0).release.perform
    expect(page.evaluate_script("document.querySelector('#astrogation-system').dataset.astrogationCenterX").to_f)
      .not_to be_within(0.001).of(page.evaluate_script("document.querySelector('#astrogation-system').dataset.astrogationShipX").to_f)

    page.find("button[aria-label='Center on ship']").click

    expect(page.evaluate_script("document.querySelector('#astrogation-system').dataset.astrogationCenterX").to_f)
      .to be_within(0.001).of(page.evaluate_script("document.querySelector('#astrogation-system').dataset.astrogationShipX").to_f)
  end

  it "handles responsive resizing and wheel input without mutating state" do
    visit "/astrogation"
    initial_markup = page.find("#astrogation-system").native.attribute("outerHTML")
    page.driver.browser.manage.window.resize_to(640, 720)
    viewport = page.find(".astrogation-scene__viewport")

    expect(viewport[:style]).to be_nil.or be_a(String)
    expect(viewport.native.size.width).to be > 0
    expect(page.evaluate_script("document.documentElement.scrollWidth")).to be <= 640

    page.execute_script(<<~JAVASCRIPT)
      document.querySelector('.astrogation-scene__viewport').dispatchEvent(
        new WheelEvent('wheel', { bubbles: true, cancelable: true, deltaY: -2 })
      )
    JAVASCRIPT

    expect(page.evaluate_script("document.querySelector('#astrogation-system').dataset.astrogationScale").to_f)
      .to be > 0.05
    expect(page.find("#astrogation-system").native.attribute("outerHTML")).to include("data-astrogation-system")
    expect(page).to have_css("[data-astrogation-entity][data-name='Ship']", visible: :all)
    expect(initial_markup).to include("data-astrogation-entities")
  end

  it "renders the same presentation after refresh without persistence" do
    visit "/astrogation"
    initial_record_counts = [ User.count, Profile.count ]
    initial_signature = page.evaluate_script(<<~JAVASCRIPT)
      JSON.stringify({
        entities: document.querySelector('#astrogation-system').dataset.astrogationEntities,
        markers: [...document.querySelectorAll('[data-astrogation-marker]')].map((marker) => marker.outerHTML),
        labels: [...document.querySelectorAll('[data-astrogation-label]')].map((label) => label.outerHTML)
      })
    JAVASCRIPT

    refresh

    expect([ User.count, Profile.count ]).to eq(initial_record_counts)
    expect(page.evaluate_script(<<~JAVASCRIPT)).to eq(initial_signature)
      JSON.stringify({
        entities: document.querySelector('#astrogation-system').dataset.astrogationEntities,
        markers: [...document.querySelectorAll('[data-astrogation-marker]')].map((marker) => marker.outerHTML),
        labels: [...document.querySelectorAll('[data-astrogation-label]')].map((label) => label.outerHTML)
      })
    JAVASCRIPT
  end
end
