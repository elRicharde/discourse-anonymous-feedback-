# name: discourse-anonymous-feedback
# about: Anonymous feedback form (door code) that sends PM to a group
# version: 0.2
# authors: Richard

enabled_site_setting :anonymous_feedback_enabled

after_initialize do
  require_dependency File.expand_path("../app/controllers/anonymous_feedback_controller.rb", __FILE__)
  
  Discourse::Application.routes.append do
    get "/anonymous-feedback" => "anonymous_feedback#index"
  end
  
  # Allow this endpoint even when login is required
  add_to_class(:application_controller, :anonymous_feedback_public) do
    skip_before_action :check_xhr, :preload_json, :verify_authenticity_token, only: [:index]
  end if defined?(ApplicationController)
  
  # Oder: Füge es direkt im Controller hinzu
  require_dependency 'application_controller'
  class ::AnonymousFeedbackController < ::ApplicationController
    skip_before_action :check_xhr, only: [:index]
    skip_before_action :preload_json, only: [:index]
    skip_before_action :redirect_to_login_if_required, only: [:index]
  end
end
