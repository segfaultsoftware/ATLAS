class ApplicationController < ActionController::Base
  before_action :require_authenticated_user!
  before_action :cache_header_avatar_key, if: :user_signed_in?

  helper_method :header_avatar_emoji

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def header_avatar_emoji
    Profile.avatar_options.fetch(session[:header_avatar_key].presence || Profile::DEFAULT_AVATAR_KEY)
  end

  def cache_header_avatar_key
    return if session[:header_avatar_user_id] == current_user.id && session[:header_avatar_key].present?

    refresh_header_avatar_key(Profile.where(user_id: current_user.id).pick(:avatar_key))
  end

  def refresh_header_avatar!(profile)
    refresh_header_avatar_key(profile&.avatar_key)
  end

  def refresh_header_avatar_key(avatar_key)
    session[:header_avatar_user_id] = current_user.id
    session[:header_avatar_key] = avatar_key.presence || Profile::DEFAULT_AVATAR_KEY
  end

  def clear_header_avatar!
    session.delete(:header_avatar_key)
    session.delete(:header_avatar_user_id)
  end

  def require_authenticated_user!
    return if user_signed_in?

    store_location_for(:user, request.fullpath) if storable_location_request?
    redirect_to root_path, status: :see_other
  end

  def storable_location_request?
    [ "GET", "HEAD" ].include?(request.request_method)
  end
end
