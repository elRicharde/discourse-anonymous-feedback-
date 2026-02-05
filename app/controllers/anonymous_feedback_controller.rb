# frozen_string_literal: true

# app/controllers/anonymous_feedback_controller.rb

class ::AnonymousFeedbackController < ::ApplicationController
  requires_plugin "discourse-anonymous-feedback"

  # Public endpoints (no login, no CSRF cookie required). We still protect via:
  # - door code
  # - global rate limits
  # - per-(HMAC) client fail/lockout buckets (no IP stored)
  skip_before_action :check_xhr, only: %i[show unlock create], raise: false
  skip_before_action :preload_json, only: %i[show unlock create], raise: false
  skip_before_action :redirect_to_login_if_required, only: %i[show unlock create], raise: false
  skip_before_action :verify_authenticity_token, only: %i[unlock create], raise: false

  # Brute force protection (per client bucket; client id = HMAC(ip, rotating secret))
  DOORCODE_MIN_INTERVAL = 2 # seconds
  DOORCODE_FAIL_BLOCKS = [
    [20, 86_400], # 1 day
    [15, 3_600],  # 1 hour
    [10, 600],    # 10 min
    [5, 60]       # 1 min
  ].freeze

  def show
    raise Discourse::NotFound unless feature_enabled?

    render "default/empty"
  end

  def unlock
    raise Discourse::NotFound unless feature_enabled?

    # Honeypot: bots fill hidden field
    if params[:website].present?
      return render json: { error: I18n.t("anonymous_feedback.errors.invalid_code") }, status: 403
    end

    # Global limiter (no IP, no hash): protects against botnets rotating IPs.
    # Setting meaning:
    #   0  => endpoint disabled (acts like feature off)
    #   >0 => max unlock attempts per hour, global for this endpoint
    limit = setting_int(:rate_limit_global_per_hour)
    if limit <= 0
      return render json: { error: I18n.t("anonymous_feedback.errors.disabled") }, status: 403
    end

    unless global_rate_limit_ok?(:unlock, limit)
      wait_s = global_rate_limit_ttl(:unlock)
      return render json: { error: I18n.t("anonymous_feedback.errors.rate_limited", seconds: wait_s) }, status: 429
    end

    # Per-client (HMAC) lockout bucket. No IP is stored. We derive an anon id:
    #   anon_id = HMAC(rotating_secret, request_ip)
    # Secret rotates every N hours (setting), and the old secret is discarded.
    # Tradeoff (accepted): after rotation, prior buckets reset.
    anon_id = anonymous_client_id
    key = redis_bucket_key(:doorcode, anon_id)
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

    door_code = params[:door_code].to_s.strip
    expected  = setting_str(:door_code).strip

    ok =
      expected.present? &&
      door_code.present? &&
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

    # success
    Discourse.redis.del(key)
    session[session_unlock_key] = true

    render json: { success: true }, status: 200
  end

  def create
    raise Discourse::NotFound unless feature_enabled?

    # Honeypot
    if params[:website].present?
      return render json: { error: I18n.t("anonymous_feedback.errors.invalid_code") }, status: 403
    end

    unless session[session_unlock_key]
      return render json: { error: I18n.t("anonymous_feedback.errors.not_unlocked") }, status: 403
    end

    # Global submit limiter (no IP, no hash)
    limit = setting_int(:rate_limit_global_per_hour)
    if limit <= 0
      return render json: { error: I18n.t("anonymous_feedback.errors.disabled") }, status: 403
    end

    unless global_rate_limit_ok?(:create, limit)
      wait_s = global_rate_limit_ttl(:create)
      return render json: { error: I18n.t("anonymous_feedback.errors.post_rate_limited", seconds: wait_s) }, status: 429
    end

    subject = params[:subject].to_s.strip
    message = params[:message].to_s

    unless subject.present? && message.present?
      return render json: { error: I18n.t("anonymous_feedback.errors.missing_fields") }, status: 400
    end

    max_len = setting_int(:max_message_length)
    if max_len > 0 && message.length > max_len
      return render json: { error: I18n.t("anonymous_feedback.errors.too_long") }, status: 400
    end

    group_name = setting_str(:target_group).strip
    if group_name.blank?
      return render json: { error: I18n.t("anonymous_feedback.errors.group_not_configured") }, status: 500
    end

    group = Group.find_by(name: group_name)
    unless group
      return render json: { error: I18n.t("anonymous_feedback.errors.group_not_found") }, status: 500
    end

    title = "#{subject_prefix}#{subject}"

    begin
      PostCreator.create!(
        posting_user,
        title: title,
        raw: message,
        archetype: Archetype.private_message,
        target_group_names: [group_name]
      )

      # One doorcode unlock = one message; forces re-unlock for next message (your preferred flow)
      session.delete(session_unlock_key)

      render json: { success: true }, status: 200
    rescue => e
      # No IP logging, no content logging (anonymity). Only error class for ops.
      Rails.logger.error("[AnonymousFeedback] create failed: #{e.class}: #{e.message}")
      render json: { error: I18n.t("anonymous_feedback.errors.send_failed") }, status: 500
    end
  end

  private

  # -------- endpoint selection (two pages, one controller) --------
  # We distinguish by path:
  #   /anonymous-feedback  => kind :af
  #   /white-board        => kind :wb
  #
  # Routes will map both to this controller (index/unlock/create).
  def kind
    p = request.path.to_s
    return :wb if p.start_with?("/white-board")
    :af
  end

  def feature_enabled?
    case kind
    when :af then SiteSetting.anonymous_feedback_enabled
    when :wb then SiteSetting.white_board_enabled
    else false
    end
  end

  # -------- settings helpers (separate settings per endpoint) --------
  def setting_str(field)
    case [kind, field]
    when [:af, :door_code] then SiteSetting.anonymous_feedback_door_code.to_s
    when [:wb, :door_code] then SiteSetting.white_board_door_code.to_s

    when [:af, :target_group] then SiteSetting.anonymous_feedback_target_group.to_s
    when [:wb, :target_group] then SiteSetting.white_board_target_group.to_s

    else ""
    end
  end

  def setting_int(field)
    case [kind, field]
    when [:af, :rate_limit_per_hour] then SiteSetting.anonymous_feedback_rate_limit_per_hour.to_i
    when [:wb, :rate_limit_per_hour] then SiteSetting.white_board_rate_limit_per_hour.to_i

    when [:af, :max_message_length] then SiteSetting.anonymous_feedback_max_message_length.to_i
    when [:wb, :max_message_length] then SiteSetting.white_board_max_message_length.to_i

    when [:af, :hmac_rotation_hours] then SiteSetting.anonymous_feedback_hmac_rotation_hours.to_i
    when [:wb, :hmac_rotation_hours] then SiteSetting.white_board_hmac_rotation_hours.to_i

    else 0
    end
  end

  # -------- subject prefix --------
  def subject_prefix
    kind == :wb ? "wb: " : "af: "
  end

  # -------- posting user (system or configured bot) --------
  def posting_user
    username =
      if kind == :wb
        SiteSetting.white_board_bot_username.to_s.strip
      else
        SiteSetting.anonymous_feedback_bot_username.to_s.strip
      end

    if username.present?
      u = User.find_by(username: username)
      return u if u && u.active?
    end

    Discourse.system_user
  end

  # -------- session key (separate per endpoint) --------
  def session_unlock_key
    "anon_feedback_unlocked:#{kind}".to_sym
  end

  # -------- global rate limits (no IP, no hash) --------
  def global_rate_key(action)
    "anon_feedback:#{kind}:#{action}:global"
  end

  def global_rate_limit_ok?(action, limit_per_hour)
    k = global_rate_key(action)
    count = Discourse.redis.incr(k)
    Discourse.redis.expire(k, 3600) if count == 1
    count <= limit_per_hour
  end

  def global_rate_limit_ttl(action)
    ttl = Discourse.redis.ttl(global_rate_key(action)).to_i
    ttl = 3600 if ttl <= 0
    ttl
  end

  # -------- anonymity-preserving client bucket (HMAC) --------
  def redis_bucket_key(scope, anon_id)
    # Important (anonymity):
    # - We do NOT store IPs.
    # - We store only HMAC(ip) where the HMAC secret rotates every N hours (setting),
    #   and old secrets are discarded -> past anon ids cannot be correlated after rotation.
    "anon_feedback:#{kind}:#{scope}:#{anon_id}"
  end

  def anonymous_client_id
    ip = request.remote_ip.to_s
    secret = current_hmac_secret
    OpenSSL::HMAC.hexdigest("SHA256", secret, ip)
  end

  def current_hmac_secret
    hours = setting_int(:hmac_rotation_hours)
    hours = 24 if hours <= 0 # sane default

    k = "anon_feedback:#{kind}:hmac_secret"
    secret = Discourse.redis.get(k)
    return secret if secret.present?

    # First use (or after expiry): generate new secret + set TTL.
    secret = SecureRandom.hex(32)
    Discourse.redis.setex(k, hours * 3600, secret)
    secret
  end
end