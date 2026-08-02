require "rails_helper"

RSpec.describe Webadmin::BaseController, type: :controller do
  def controller_with_user(user)
    described_class.new.tap do |controller|
      allow(controller).to receive(:current_user).and_return(user)
      allow(controller).to receive(:root_path).and_return("/")
    end
  end

  it "enforces Webadmin authorization for descendant controllers" do
    filters = described_class._process_action_callbacks.map(&:filter)

    expect(filters).to include(:require_webadmin!)
  end

  it "redirects authenticated Users" do
    controller = controller_with_user(FactoryBot.build(:user))
    expect(controller).to receive(:redirect_to).with(
      "/",
      alert: "Webadmin access required.",
      status: :see_other
    )

    controller.send(:require_webadmin!)
  end

  it "does not redirect Webadmins" do
    controller = controller_with_user(FactoryBot.build(:user, role: :webadmin))

    expect(controller).not_to receive(:redirect_to)

    controller.send(:require_webadmin!)
  end
end
