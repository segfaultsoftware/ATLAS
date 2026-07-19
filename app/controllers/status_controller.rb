class StatusController < ApplicationController
  skip_before_action :require_authenticated_user!

  def show
  end
end
