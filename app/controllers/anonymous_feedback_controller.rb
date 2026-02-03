# frozen_string_literal: true

class ::AnonymousFeedbackController < ::ApplicationController
  requires_plugin ::AnonymousFeedback::PLUGIN_NAME

  skip_before_action :check_xhr, only: [:index, :create], raise: false
  skip_before_action :preload_json, only: [:index, :create], raise: false
  skip_before_action :redirect_to_login_if_required, only: [:index, :create], raise: false
  skip_before_action :verify_authenticity_token, only: [:create], raise: false

  def index
    render :index
  end

  def create
    # Honeypot
    return render json: { success: true }, status: 200 if params[:website].present?

    door_code = params[:door_code].to_s
    subject   = params[:subject].to_s.strip
    message   = params[:message].to_s

    unless door_code.present? && subject.present? && message.present?
      return render json: { error: I18n.t("anonymous_feedback.errors.missing_fields") }, status: 400
    end

    # Doorcode-Check kommt in Chapter 4
    render json: { success: true }, status: 200
  end
end
