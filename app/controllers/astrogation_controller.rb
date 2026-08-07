class AstrogationController < ApplicationController
  skip_before_action :require_authenticated_user!

  def show
    @entities = Astrogation::System.entities
  end
end
