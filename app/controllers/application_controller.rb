class ApplicationController < ActionController::Base
  before_action :require_authenticated_user!

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def require_authenticated_user!
    return if user_signed_in?

    store_location_for(:user, request.fullpath) if storable_location_request?
    redirect_to root_path, status: :see_other
  end

  def storable_location_request?
    [ "GET", "HEAD" ].include?(request.request_method)
  end
end
