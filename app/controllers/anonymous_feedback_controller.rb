# frozen_string_literal: true

class ::AnonymousFeedbackController < ::ApplicationController
  requires_plugin "discourse-anonymous-feedback"

  skip_before_action :check_xhr, only: %i[index unlock create], raise: false
  skip_before_action :preload_json, only: %i[index unlock create], raise: false
  skip_before_action :redirect_to_login_if_required, only: %i[index unlock create], raise: false
  skip_before_action :verify_authenticity_token, only: %i[unlock create], raise: false

  # DoorCode RateLimit:
  # 1 / 2 Sekunden
  # nach 5  -> 1 min
  # nach 10 -> 10 min
  # nach 15 -> 1 h
  # nach 20 -> 1 Tag
  DOORCODE_MIN_INTERVAL = 2 # seconds
  DOORCODE_FAIL_BLOCKS = [
    [20, 86_400], # 1 day
    [15, 3_600],  # 1 hour
    [10, 600],    # 10 min
    [5, 60]       # 1 min
  ].freeze

  def index
    render :index, layout: false
  end

  # Türcode prüfen + "freischalten" (Session-Flag)
  def unlock
    return render json: { success: true }, status: 200 if params[:website].present? # Honeypot

    ip  = request.remote_ip.to_s
    key = "anon_feedback:doorcode:#{ip}"
    now = Time.now.to_i

    # Block aktiv?
    blocked_until = Discourse.redis.hget(key, "blocked_until").to_i
    if blocked_until > now
      wait_s = blocked_until - now
      return render json: { error: I18n.t("anonymous_feedback.errors.rate_limited", seconds: wait_s) }, status: 429
    end

    # 1 Versuch / 2 Sekunden
    last_attempt = Discourse.redis.hget(key, "last_attempt").to_i
    if last_attempt > 0 && (now - last_attempt) < DOORCODE_MIN_INTERVAL
      wait_s = DOORCODE_MIN_INTERVAL - (now - last_attempt)
      return render json: { error: I18n.t("anonymous_feedback.errors.rate_limited", seconds: wait_s) }, status: 429
    end

    Discourse.redis.hset(key, "last_attempt", now)
    Discourse.redis.expire(key, 86_400) # state max 1 Tag halten

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

      return render json: { error: I18n.t("anonymous_feedback.errors.invalid_code") }, status: 403
    end

    # Erfolg: DoorCode-Limits zurücksetzen
    Discourse.redis.del(key)

    session[:anon_feedback_unlocked] = true
    render json: { success: true }, status: 200
  end

  def create
    return render json: { success: true }, status: 200 if params[:website].present? # Honeypot

    unless session[:anon_feedback_unlocked]
      return render json: { error: I18n.t("anonymous_feedback.errors.invalid_code") }, status: 403
    end

    # Post/PM RateLimit aus Settings verwenden (anonymous_feedback_rate_limit_per_hour)
    limit_per_hour = SiteSetting.anonymous_feedback_rate_limit_per_hour.to_i
    if limit_per_hour > 0
      ip = request.remote_ip.to_s
      rl_key = "anon_feedback:post:ip:#{ip}"

      # Zähler + expiry auf 1 Stunde (sliding-ish genug für den Zweck)
      count = Discourse.redis.incr(rl_key)
      Discourse.redis.expire(rl_key, 3600) if count == 1

      if count > limit_per_hour
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
      return render json: { error: "Target group not configured" }, status: 500
    end
    
    # Prüfe ob Gruppe existiert
    group = Group.find_by(name: group_name)
    unless group
      Rails.logger.error("[AnonymousFeedback] Target group '#{group_name}' does not exist")
      return render json: { error: I18n.t("anonymous_feedback.errors.group_not_found") }, status: 500
    end

    # PostCreator inkl error Handling
    begin
      post = PostCreator.create!(
        Discourse.system_user,
        title: subject,
        raw: message,
        archetype: Archetype.private_message,
        target_group_names: [group_name]
      )

      # nach erfolgreichem Senden wieder "sperren"
      session.delete(:anon_feedback_unlocked)

      Rails.logger.info("[AnonymousFeedback] Successfully created PM to group '#{group_name}' from IP #{request.remote_ip}")
      render json: { success: true }, status: 200
    rescue => e
      Rails.logger.error("[AnonymousFeedback] Failed to create PM: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: I18n.t("anonymous_feedback.errors.send_failed") }, status: 500
    end
  end
end
