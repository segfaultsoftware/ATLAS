class AstrogationController < ApplicationController
  skip_before_action :require_authenticated_user!

  def show
    @entities = Astrogation::System.entities
    @transits = Astrogation::System.transits
    @star_class = Astrogation::StarCatalog.normalize(params[:starclass])
    @star_properties = Astrogation::StarCatalog.lookup(@star_class)
  end
end
