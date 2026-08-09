module Users
  class RegistrationsController < Devise::RegistrationsController
    protected

    def build_resource(hash = {})
      super
      resource.build_profile(preferred_name: resource.preferred_name)
    end

    def sign_up_params
      devise_parameter_sanitizer.permit(:sign_up, keys: [ :preferred_name ])
      super
    end
  end
end
