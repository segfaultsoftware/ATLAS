require "selenium-webdriver"
require "json"

module AstrogationSystemTesting
  SCREEN_SIZE = [ 1280, 900 ].freeze
  ASTROGATION_ENTITY_NAMES = [
    "Tejat A", "Tejat B", "Tejat C", "Ketrak Station", "Gate Alpha", "Gate Beta", "Ship"
  ].freeze
  LAYOUT_WAIT_TIMEOUT = 5
  LAYOUT_WAIT_INTERVAL = 0.05
  LAYOUT_STABLE_SAMPLES = 2

  module_function

  def configure_chrome_options(options)
    binary = ENV["ASTROGATION_CHROME_BINARY"]
    options.binary = binary if binary && File.executable?(binary)
    options.add_argument("--headless=new")
    options.add_argument("--disable-gpu")
    options.add_argument("--no-sandbox") if Process.uid.zero?
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--window-size=#{SCREEN_SIZE.join(",")}")
  end

  def chrome_options
    options = Selenium::WebDriver::Chrome::Options.new
    configure_chrome_options(options)
    options
  end

  def verify_browser!
    browser = Selenium::WebDriver.for(:chrome, options: chrome_options)
    browser.quit
  rescue StandardError => e
    raise "Astrogation system-test browser startup failed; headless Chrome is required: #{e.class}: #{e.message}"
  end

  def wait_for_stable_astrogation_layout(
    page,
    expected_names: ASTROGATION_ENTITY_NAMES,
    timeout: LAYOUT_WAIT_TIMEOUT,
    poll_interval: LAYOUT_WAIT_INTERVAL,
    stable_samples: LAYOUT_STABLE_SAMPLES
  )
    raise ArgumentError, "timeout must be positive" unless timeout.positive?
    raise ArgumentError, "poll_interval must be positive" unless poll_interval.positive?
    raise ArgumentError, "stable_samples must be positive" unless stable_samples.positive?

    expected_names = Array(expected_names).map(&:to_s)
    raise ArgumentError, "expected_names must not be empty" if expected_names.empty?

    wait = Selenium::WebDriver::Wait.new(timeout: timeout, interval: poll_interval)
    previous_sample = nil
    consecutive_samples = 0

    wait.until do
      sample = page.evaluate_script(astrogation_layout_sample_script(expected_names))

      if sample.nil?
        previous_sample = nil
        consecutive_samples = 0
      elsif sample == previous_sample
        consecutive_samples += 1
      else
        previous_sample = sample
        consecutive_samples = 1
      end

      sample if consecutive_samples >= stable_samples
    end
  end

  def astrogation_layout_sample_script(expected_names)
    serialized_names = JSON.generate(expected_names)

    <<~JAVASCRIPT
      (() => {
        const expectedNames = #{serialized_names}
        const system = document.querySelector('#astrogation-system[data-astrogation-system]')
        if (!system) return null

        const markers = [...system.querySelectorAll('[data-astrogation-marker]')]
        const labels = [...system.querySelectorAll('[data-astrogation-label]')]
        if (markers.length !== expectedNames.length || labels.length !== expectedNames.length) return null

        const finiteRectangle = (rectangle) => rectangle && [
          rectangle.left, rectangle.top, rectangle.right, rectangle.bottom,
          rectangle.width, rectangle.height
        ].every(Number.isFinite)

        const rectangleValues = (rectangle) => ({
          left: rectangle.left,
          top: rectangle.top,
          right: rectangle.right,
          bottom: rectangle.bottom,
          width: rectangle.width,
          height: rectangle.height
        })

        const finiteScreenTransform = (element) => {
          const matrix = element.getScreenCTM()
          if (!matrix) return null

          const values = [matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f]
          return values.every(Number.isFinite) ? values : null
        }

        const entities = expectedNames.map((name) => {
          const marker = markers.find((candidate) => candidate.dataset.astrogationMarker === name)
          const label = labels.find((candidate) => candidate.dataset.astrogationLabel === name)
          if (!marker || !label) return null

          const markerRect = marker.getBoundingClientRect()
          const labelRect = label.getBoundingClientRect()
          const markerScreenTransform = finiteScreenTransform(marker)
          const labelScreenTransform = finiteScreenTransform(label)
          if (!finiteRectangle(markerRect) || !finiteRectangle(labelRect)) return null
          if (!markerScreenTransform || !labelScreenTransform) return null

          return {
            name,
            markerRect: rectangleValues(markerRect),
            labelRect: rectangleValues(labelRect),
            markerScreenTransform,
            labelScreenTransform
          }
        })

        return entities.every(Boolean) ? { entities } : null
      })()
    JAVASCRIPT
  end
end
