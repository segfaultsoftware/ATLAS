class ProfilesController < ApplicationController
  def show
    @profile = requested_profile
  end

  private

  def requested_profile
    if params[:id].present?
      Profile.find(params[:id])
    else
      current_user.profile || current_user.ensure_profile!(preferred_name: current_user.name)
    end
  end
end
