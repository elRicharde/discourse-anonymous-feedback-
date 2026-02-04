# frozen_string_literal: true

class ::AnonymousFeedbackController < ::ApplicationController
  requires_plugin "discourse-anonymous-feedback"

  skip_before_action :check_xhr, only: %i[index unlock create], raise: false
  skip_before_action :preload_json, only: %i[index unlock create], raise: false
  skip_before_action :redirect_to_login_if_required, only: %i[index unlock create], raise: false
  skip_before_action :verify_authenticity_token, only: %i[unlock create], raise: false

  DOORCODE_MIN_INTERVAL = 2 # seconds
  DOORCODE_FAIL_BLOCKS = [
    [20, 86_400], # 1 day
    [15, 3_600],  # 1 hour
    [10, 600],    # 10 min
    [5, 60]       # 1 min
  ].freeze

  def index
    return if performed?
    render :index, layout: false
  end

  def unlock
    return if performed?

    if params[:website].present?
      Rails.logger.warn("[AnonymousFeedback] Honeypot triggered from IP #{request.remote_ip}")
      return render json: { error: I18n.t("anonymous_feedback.errors.invalid_code") }, status: 403
    end

    ip  = request.remote_ip.to_s
    key = "anon_feedback:doorcode:#{ip}"
    now = Time.now.to_i

    blocked_until = Discourse.redis.hget(key, "blocked_until").to_i
    if blocked_until > now
      wait_s = blocked_until - now
      return render json: { error: I18n.t("anonymous_feedback.errors.rate_limited", seconds: wait_s) }, status: 429
    end

    last_attempt = Discourse.redis.hget(key, "last_attempt").to_i
    if last_attempt > 0 && (now - last_attempt) < DOORCODE_MIN_INTERVAL
      wait_s = DOORCODE_MIN_INTERVAL - (now - last_attempt)
      return render json: { error: I18n.t("anonymous_feedback.errors.rate_limited", seconds: wait_s) }, status: 429
    end

    Discourse.redis.hset(key, "last_attempt", now)
    Discourse.redis.expire(key, 86_400)

    door_code = params[:door_code].to_s
    expected  = SiteSetting.anonymous_feedback_door_code.to_s

    ok = expected.present? &&
      ActiveSupport::SecurityUtils.secure_compare(
        ::Digest::SHA256.hexdigest(door_code),
        ::Digest::SHA256.hexdigest(expected)
      )

    unless ok
      fails = Discourse.redis.hincrby(key, "fail_count", 1)
      block_seconds = DOORCODE_FAIL_BLOCKS.find { |threshold, _| fails >= threshold }&.last
      Discourse.redis.hset(key, "blocked_until", now + block_seconds) if block_seconds

      Rails.logger.warn("[AnonymousFeedback] Failed unlock attempt from IP #{ip} (#{fails} fails)")
      return render json: { error: I18n.t("anonymous_feedback.errors.invalid_code") }, status: 403
    end

    Discourse.redis.del(key)
    session[:anon_feedback_unlocked] = true
    Rails.logger.info("[AnonymousFeedback] Successful unlock from IP #{ip}")

    return render json: { success: true }, status: 200
  end

  def create
    return if performed?

    if params[:website].present?
      Rails.logger.warn("[AnonymousFeedback] Honeypot triggered in create from IP #{request.remote_ip}")
      return render json: { error: I18n.t("anonymous_feedback.errors.invalid_code") }, status: 403
    end

    unless session[:anon_feedback_unlocked]
      return render json: { error: I18n.t("anonymous_feedback.errors.not_unlocked") }, status: 403
    end

    limit_per_hour = SiteSetting.anonymous_feedback_rate_limit_per_hour.to_i
    if limit_per_hour > 0
      ip = request.remote_ip.to_s
      rl_key = "anon_feedback:post:ip:#{ip}"

      count = Discourse.redis.incr(rl_key)
      Discourse.redis.expire(rl_key, 3600) if count == 1

      # Wichtig: ab dem Limit blocken (nicht erst drüber)
      if count >= limit_per_hour
        ttl = Discourse.redis.ttl(rl_key).to_i
        ttl = 3600 if ttl <= 0
        return render json: { error: I18n.t("anonymous_feedback.errors.post_rate_limited", seconds: ttl) }, status: 429
      end
    end

    subject = params[:subject].to_s.strip
    message = params[:message].to_s

    unless subject.present? && message.present?
      return render json: { error: I18n.t("anonymous_feedback.errors.missing_fields") }, status: 400
    end

    max_len = SiteSetting.anonymous_feedback_max_message_length.to_i
    if max_len > 0 && message.length > max_len
      return render json: { error: I18n.t("anonymous_feedback.errors.too_long") }, status: 400
    end

    group_name = SiteSetting.anonymous_feedback_target_group.to_s.strip
    if group_name.blank?
      Rails.logger.error("[AnonymousFeedback] Target group not configured")
      return render json: { error: I18n.t("anonymous_feedback.errors.group_not_configured") }, status: 500
    end

    group = Group.find_by(name: group_name)
    unless group
      Rails.logger.error("[AnonymousFeedback] Target group '#{group_name}' does not exist")
      return render json: { error: I18n.t("anonymous_feedback.errors.group_not_found") }, status: 500
    end

    begin
      PostCreator.create!(
        Discourse.system_user,
        title: subject,
        raw: message,
        archetype: Archetype.private_message,
        target_group_names: [group_name]
      )

      session.delete(:anon_feedback_unlocked)

      Rails.logger.info("[AnonymousFeedback] Successfully created PM to group '#{group_name}' from IP #{request.remote_ip}")
      return render json: { success: true }, status: 200
    rescue => e
      Rails.logger.error("[AnonymousFeedback] Failed to create PM: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      return render json: { error: I18n.t("anonymous_feedback.errors.send_failed") }, status: 500
    end
  end
end
