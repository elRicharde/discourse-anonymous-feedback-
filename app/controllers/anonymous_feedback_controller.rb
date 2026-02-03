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
    door_code = params[:door_code].to_s
    message   = params[:message].to_s

    unless door_code.present? && message.present?
      return render json: { error: I18n.t("anonymous_feedback.errors.missing_fields") }, status: 400
    end

    # Chapter später: doorcode prüfen, ratelimit, PM senden
    render json: { success: true }
  rescue => e
    render json: { error: e.message }, status: 500
  end
end
