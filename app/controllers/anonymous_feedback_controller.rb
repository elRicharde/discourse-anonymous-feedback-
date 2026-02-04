# frozen_string_literal: true

class ::AnonymousFeedbackController < ::ApplicationController
  requires_plugin "discourse-anonymous-feedback"

  skip_before_action :check_xhr, only: [:index, :create], raise: false
  skip_before_action :preload_json, only: [:index, :create], raise: false
  skip_before_action :redirect_to_login_if_required, only: [:index, :create], raise: false
  skip_before_action :verify_authenticity_token, only: [:create], raise: false

  def index
    render :index, layout: false
  end
  
  def create
    # Honeypot
    return render json: { success: true }, status: 200 if params[:website].present?
  
    door_code = params[:door_code].to_s
    subject   = params[:subject].to_s.strip
    message = params[:message].to_s.strip
  
    unless door_code.present? && subject.present? && message.present?
      return render json: { error: I18n.t("anonymous_feedback.errors.missing_fields") }, status: 400
    end
  
    expected = SiteSetting.anonymous_feedback_door_code.to_s
  
    # Doorcode prüfen (konstantzeit-compare)
    ok = expected.present? &&
         ActiveSupport::SecurityUtils.secure_compare(
           ::Digest::SHA256.hexdigest(door_code),
           ::Digest::SHA256.hexdigest(expected)
         )
  
    unless ok
      return render json: { error: I18n.t("anonymous_feedback.errors.invalid_code") }, status: 403
    end
  
    group_name = SiteSetting.anonymous_feedback_target_group.to_s.strip
    if group_name.blank?
      return render json: { error: "Target group not configured" }, status: 500
    end
  
    PostCreator.create!(
      Discourse.system_user,
      title: subject,
      raw: message,
      archetype: Archetype.private_message,
      target_group_names: [group_name]
    )
  
    render json: { success: true }, status: 200
  end
end
