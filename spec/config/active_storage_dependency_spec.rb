require "bundler/setup"

RSpec.describe "Active Storage dependency" do
  it "resolves Rails and Active Storage at the patched release or later" do
    rails_components = %w[
      actioncable
      actionmailbox
      actionmailer
      actionpack
      actiontext
      actionview
      activejob
      activemodel
      activerecord
      activestorage
      activesupport
      rails
      railties
    ]
    minimum_version = Gem::Version.new("8.1.3.1")

    rails_components.each do |component|
      resolved_version = Gem::Specification.find_by_name(component).version

      expect(resolved_version).to be >= minimum_version
    end
  end
end
