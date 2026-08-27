module Users
  class RegistrationsController < Devise::RegistrationsController
    protected

    def build_resource(hash = {})
      super
      resource.build_profile
    end
  end
end
