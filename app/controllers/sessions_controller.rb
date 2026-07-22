class SessionsController < ApplicationController
  include Devise::Controllers::Rememberable

  before_action :authenticate_user!

  def destroy
    forget_me(current_user)
    sign_out(:user)
    clear_header_avatar!
    redirect_to root_path, status: :see_other
  end
end
