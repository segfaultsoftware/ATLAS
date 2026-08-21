require "spec_helper"
require_relative "browser_system_testing"

RSpec.describe BrowserSystemTesting do
  describe ".configure_chrome_options" do
    it "configures a shared headless browser viewport" do
      options = double("Chrome options")
      allow(options).to receive(:binary=)
      allow(options).to receive(:add_argument)

      described_class.configure_chrome_options(options)

      expect(options).to have_received(:add_argument).with("--headless=new")
      expect(options).to have_received(:add_argument).with("--disable-gpu")
      expect(options).to have_received(:add_argument).with("--disable-dev-shm-usage")
      expect(options).to have_received(:add_argument).with("--window-size=1280,900")
    end
  end
end
