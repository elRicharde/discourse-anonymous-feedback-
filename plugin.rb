# name: discourse-anonymous-feedback
# about: Anonymous feedback form (door code) that sends PM to a group
# version: 0.3
# authors: Richard

enabled_site_setting :anonymous_feedback_enabled

after_initialize do
  module ::AnonymousFeedback
    PLUGIN_NAME = "discourse-anonymous-feedback"
  end
  register_asset "javascripts/discourse/anonymous-feedback.js"
end


  # Load controller
  require_dependency File.expand_path("../app/controllers/anonymous_feedback_controller.rb", __FILE__)

  # Routes
Discourse::Application.routes.append do
  get  "/anonymous-feedback" => "anonymous_feedback#index"
  post "/anonymous-feedback/unlock" => "anonymous_feedback#unlock"
  post "/anonymous-feedback" => "anonymous_feedback#create"
end


  # Ensure Rails can find plugin views for this controller
  # (needed in some Discourse/Rails setups when using custom controllers)
  view_path = File.expand_path("../app/views", __FILE__)
  ActiveSupport.on_load(:action_controller) do
    if defined?(::AnonymousFeedbackController)
      ::AnonymousFeedbackController.prepend_view_path(view_path)
    end
  end
end
