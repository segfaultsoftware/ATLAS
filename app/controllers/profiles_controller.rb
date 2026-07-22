class ProfilesController < ApplicationController
  def show
    @profile = requested_profile
  end

  def edit
    @profile = current_profile
  end

  def update
    @profile = current_profile

    if @profile.update(profile_params)
      redirect_to profile_path, status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def requested_profile
    if params[:id].present?
      Profile.find(params[:id])
    else
      current_profile
    end
  end

  def current_profile
    current_user.profile || current_user.ensure_profile!(preferred_name: current_user.name)
  end

  def profile_params
    params.require(:profile).permit(:preferred_name, :pronouns, :preferred_playtimes, :avatar_key)
  end
end
