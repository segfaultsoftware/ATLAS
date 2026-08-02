module Webadmin
  class BaseController < ApplicationController
    before_action :require_webadmin!
  end
end
