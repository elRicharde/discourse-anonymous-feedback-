class AnonymousFeedbackController < ApplicationController
  skip_before_action :check_xhr, only: [:index]
  skip_before_action :preload_json, only: [:index]
  skip_before_action :redirect_to_login_if_required, only: [:index]
  skip_before_action :verify_authenticity_token, only: [:create]
  
  def index
    # Dein Code hier
  end
  
  def create
    # Dein Code zum Senden der Nachricht
  end
end


# name: discourse-anonymous-feedback
# about: Anonymous feedback form (door code) that sends PM to a group
# version: 0.2
# authors: Richard

enabled_site_setting :anonymous_feedback_enabled

after_initialize do
  require_dependency File.expand_path("../app/controllers/anonymous_feedback_controller.rb", __FILE__)
  
  Discourse::Application.routes.append do
    get "/anonymous-feedback" => "anonymous_feedback#index"
    post "/anonymous-feedback" => "anonymous_feedback#create"
  end
end
