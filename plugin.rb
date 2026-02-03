# name: discourse-anonymous-feedback
# about: Anonymous feedback form (door code) that sends PM to a group
# version: 0.1
# authors: Richard

enabled_site_setting :anonymous_feedback_enabled

after_initialize do
  Discourse::Application.routes.append do
    get "/anonymous-feedback" => "anonymous_feedback#index"
  end
end

