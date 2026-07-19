module Users
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    include Devise::Controllers::Rememberable

    skip_before_action :require_authenticated_user!

    def google_oauth2
      user = User.find_or_create_from_google_oauth!(request.env.fetch("omniauth.auth"))

      sign_in(user)
      remember_me(user)
      redirect_to stored_location_for(:user) || root_path, status: :see_other
    end

    def failure
      redirect_to root_path, status: :see_other
    end
  end
end
