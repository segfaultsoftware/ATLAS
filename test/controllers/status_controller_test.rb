require "test_helper"

class StatusControllerTest < ActionDispatch::IntegrationTest
  test "renders the status thumbs up" do
    get "/status"

    assert_response :success
    assert_select "button.status-thumb", text: "👍"
    assert_select '[data-controller="status-thumb"]'
  end
end
