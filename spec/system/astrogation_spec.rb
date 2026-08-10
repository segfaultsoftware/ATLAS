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

  it "renders each transit as a directional light-yellow arrow through navigation" do
    FactoryBot.create(
      :celestial_transit,
      celestial_coordinates_start_x: -24.433,
      celestial_coordinates_start_y: 1399.787,
      celestial_coordinates_target_x: -1285.575,
      celestial_coordinates_target_y: -1532.089
    )

    visit "/astrogation"

    page.find("[data-astrogation-transit='0']")
    transit_attributes = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const transit = document.querySelector('[data-astrogation-transit="0"]')
        return {
          x1: transit.getAttribute('x1'),
          y1: transit.getAttribute('y1'),
          x2: transit.getAttribute('x2'),
          y2: transit.getAttribute('y2'),
          markerEnd: transit.getAttribute('marker-end'),
          stroke: getComputedStyle(transit).stroke,
          strokeDasharray: getComputedStyle(transit).strokeDasharray
        }
      })()
    JAVASCRIPT

    expect(transit_attributes).to eq(
      {
        "x1" => "-24.433",
        "y1" => "1399.787",
        "x2" => "-1285.575",
        "y2" => "-1532.089",
        "markerEnd" => "url(#astrogation-transit-arrowhead)",
        "stroke" => "rgb(255, 248, 197)",
        "strokeDasharray" => "none"
      }
    )

    initial_transform = page.find("[data-astrogation-scene-target='world']")["transform"]
    page.find("button[aria-label='Zoom in']").click
    expect(page).to have_css("[data-astrogation-transit='0']", count: 1)
    expect(page.find("[data-astrogation-scene-target='world']")["transform"]).not_to eq(initial_transform)

    viewport = page.find(".astrogation-scene__viewport")
    page.driver.browser.action.move_to(viewport.native).click_and_hold.move_by(80, 0).release.perform
    expect(page).to have_css("[data-astrogation-transit='0']", count: 1)

    page.find("button[aria-label='Center on ship']").click
    expect(page).to have_css("[data-astrogation-transit='0']", count: 1)

    page.driver.browser.manage.window.resize_to(640, 720)
    expect(page).to have_css("[data-astrogation-transit='0']", count: 1)

    refresh
    expect(page).to have_css("[data-astrogation-transit='0']", count: 1)
  end

  it "logs and omits malformed transits without affecting valid records" do
    visit "/astrogation"

    result = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const element = document.querySelector('#astrogation-system')
        const controller = window.Stimulus.getControllerForElementAndIdentifier(element, 'astrogation-scene')
        const messages = []
        const originalLog = console.log
        console.log = (...arguments) => messages.push(arguments)

        try {
          controller.transits = [
            { celestial_coordinates_start: { x: 1, y: 2 } },
            {
              celestial_coordinates_start: { x: 5, y: 6 },
              celestial_coordinates_target: { x: 5, y: 6 }
            },
            {
              celestial_coordinates_start: { x: 1, y: 2 },
              celestial_coordinates_target: { x: 3, y: 4 }
            }
          ]
          controller.render()
        } finally {
          console.log = originalLog
        }

        return {
          transitCount: document.querySelectorAll('[data-astrogation-transit]').length,
          logCount: messages.length
        }
      })()
    JAVASCRIPT

    expect(result).to eq("transitCount" => 1, "logCount" => 2)
  end

  it "keeps every entity label above its marker with a screen-space gap" do
    expect(AstrogationSystemTesting).to receive(:wait_for_stable_astrogation_layout).exactly(4).times.and_call_original

    visit "/astrogation"

    expect_entity_labels_above_markers

    page.find("button[aria-label='Zoom in']").click
    expect_entity_labels_above_markers

    viewport = page.find(".astrogation-scene__viewport")
    page.driver.browser.action.move_to(viewport.native).click_and_hold.move_by(80, 0).release.perform
    expect_entity_labels_above_markers

    page.driver.browser.manage.window.resize_to(640, 720)
    expect_entity_labels_above_markers
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
    expect(AstrogationSystemTesting).to receive(:wait_for_stable_astrogation_layout).twice.and_call_original

    visit "/astrogation"
    initial_record_counts = [ User.count, Profile.count ]
    AstrogationSystemTesting.wait_for_stable_astrogation_layout(page)
    initial_signature = page.evaluate_script(<<~JAVASCRIPT)
      JSON.stringify({
        entities: document.querySelector('#astrogation-system').dataset.astrogationEntities,
        markers: [...document.querySelectorAll('[data-astrogation-marker]')].map((marker) => marker.outerHTML),
        labels: [...document.querySelectorAll('[data-astrogation-label]')].map((label) => {
          const staticLabel = label.cloneNode(true)
          staticLabel.removeAttribute('transform')
          return staticLabel.outerHTML
        })
      })
    JAVASCRIPT

    refresh
    AstrogationSystemTesting.wait_for_stable_astrogation_layout(page)

    expect([ User.count, Profile.count ]).to eq(initial_record_counts)
    expect(page.evaluate_script(<<~JAVASCRIPT)).to eq(initial_signature)
      JSON.stringify({
        entities: document.querySelector('#astrogation-system').dataset.astrogationEntities,
        markers: [...document.querySelectorAll('[data-astrogation-marker]')].map((marker) => marker.outerHTML),
        labels: [...document.querySelectorAll('[data-astrogation-label]')].map((label) => {
          const staticLabel = label.cloneNode(true)
          staticLabel.removeAttribute('transform')
          return staticLabel.outerHTML
        })
      })
    JAVASCRIPT
  end

  private

  def expect_entity_labels_above_markers
    layout = AstrogationSystemTesting.wait_for_stable_astrogation_layout(page)
    geometries = layout.fetch("entities").map do |entity|
      marker_rect = entity.fetch("markerRect")
      label_rect = entity.fetch("labelRect")

      {
        "name" => entity.fetch("name"),
        "topGap" => marker_rect.fetch("top") - label_rect.fetch("bottom"),
        "centerDelta" => ((label_rect.fetch("left") + label_rect.fetch("right")) / 2) -
          ((marker_rect.fetch("left") + marker_rect.fetch("right")) / 2)
      }
    end

    expect(geometries.map { |geometry| geometry["name"] }).to contain_exactly(
      "Tejat A", "Tejat B", "Tejat C", "Ketrak Station", "Gate Alpha", "Gate Beta", "Ship"
    )
    geometries.each do |geometry|
      expect(geometry["topGap"]).to be_within(0.5).of(4)
      expect(geometry["centerDelta"]).to be_within(0.5).of(0)
    end
  end
end
