require "selenium-webdriver"

module BrowserSystemTesting
  SCREEN_SIZE = [ 1280, 900 ].freeze

  module_function

  def configure_chrome_options(options)
    binary = ENV["CHROME_BINARY"]
    options.binary = binary if binary && File.executable?(binary)
    options.add_argument("--headless=new")
    options.add_argument("--disable-gpu")
    options.add_argument("--no-sandbox") if Process.uid.zero?
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--window-size=#{SCREEN_SIZE.join(",")}")
  end

  def chrome_options
    Selenium::WebDriver::Chrome::Options.new.tap do |options|
      configure_chrome_options(options)
    end
  end

  def verify_browser!
    browser = Selenium::WebDriver.for(:chrome, options: chrome_options)
    browser.quit
  rescue StandardError => error
    raise "System-test browser startup failed; headless Chrome is required: #{error.class}: #{error.message}"
  end
end
