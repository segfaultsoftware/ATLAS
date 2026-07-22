class ProfilesController < ApplicationController
  def show
    @profile = requested_profile
  end

  def edit
    @profile = ensure_current_profile
  end

  def update
    @profile = ensure_current_profile

    if @profile.update(profile_params)
      refresh_header_avatar!(@profile)
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
      ensure_current_profile
    end
  end

  def ensure_current_profile
    current_user.profile || current_user.ensure_profile!(preferred_name: current_user.name)
  end

  def profile_params
    params.require(:profile).permit(:preferred_name, :pronouns, :preferred_playtimes, :avatar_key)
  end
end
