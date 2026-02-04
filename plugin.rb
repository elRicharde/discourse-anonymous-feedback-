# frozen_string_literal: true

# name: discourse-anonymous-feedback
# about: Public doorcode form that sends PM to a group (2 endpoints: anonymous-feedback + white-board)
# version: 0.95
# authors: Richard

enabled_site_setting :anonymous_feedback_enabled
enabled_site_setting :white_board_enabled

after_initialize do
  module ::AnonymousFeedback
    PLUGIN_NAME = "discourse-anonymous-feedback"
  end

  # Controller
  require_dependency File.expand_path("../app/controllers/anonymous_feedback_controller.rb", __FILE__)

  # Routes (addresses are intentionally NOT configurable)
  Discourse::Application.routes.append do
    get  "/anonymous-feedback"        => "anonymous_feedback#index"
    post "/anonymous-feedback/unlock" => "anonymous_feedback#unlock"
    post "/anonymous-feedback"        => "anonymous_feedback#create"

    get  "/white-board"        => "anonymous_feedback#index"
    post "/white-board/unlock" => "anonymous_feedback#unlock"
    post "/white-board"        => "anonymous_feedback#create"
  end

  # Ensure plugin views are discoverable (safe even if you later drop ERB view)
  view_path = File.expand_path("../app/views", __FILE__)
  ActiveSupport.on_load(:action_controller) do
    if defined?(::AnonymousFeedbackController)
      ::AnonymousFeedbackController.prepend_view_path(view_path)
    end
  end
end
