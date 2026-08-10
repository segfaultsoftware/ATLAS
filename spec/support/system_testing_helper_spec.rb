require "spec_helper"
require_relative "system_testing"

RSpec.describe AstrogationSystemTesting do
  describe ".wait_for_stable_astrogation_layout" do
    it "uses bounded Selenium polling until the same usable sample is consecutive" do
      page = instance_double("Capybara::Session")
      sample = { "entities" => [ { "name" => "Ship" } ] }
      allow(page).to receive(:evaluate_script).and_return(nil, sample, sample)

      wait = instance_double(Selenium::WebDriver::Wait)
      expect(Selenium::WebDriver::Wait).to receive(:new)
        .with(timeout: 3, interval: 0.01)
        .and_return(wait)
      allow(wait).to receive(:until) do |&condition|
        result = nil
        3.times do
          result = condition.call
          break if result
        end
        result
      end

      expect(
        described_class.wait_for_stable_astrogation_layout(
          page,
          timeout: 3,
          poll_interval: 0.01,
          stable_samples: 2
        )
      ).to eq(sample)
      expect(page).to have_received(:evaluate_script).exactly(3).times
    end
  end
end
