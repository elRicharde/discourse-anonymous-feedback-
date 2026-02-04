# frozen_string_literal: true

class ::AnonymousFeedbackController < ::ApplicationController
  requires_plugin "discourse-anonymous-feedback"

  # Seite + JSON-API müssen ohne Login erreichbar sein
  skip_before_action :check_xhr, only: %i[show unlock create], raise: false
  skip_before_action :preload_json, only: %i[show unlock create], raise: false
  skip_before_action :redirect_to_login_if_required, only: %i[show unlock create], raise: false

  # CSRF NICHT abschalten: Discourse ajax() sendet Token automatisch
  # => dadurch sind die öffentlichen POSTs deutlich härter gegen CSRF.

  DOORCODE_MIN_INTERVAL = 2 # seconds
  DOORCODE_FAIL_BLOCKS = [
    [20, 86_400], # 1 day
    [15, 3_600],  # 1 hour
    [10, 600],    # 10 min
    [5, 60]       # 1 min
  ].freeze

  # HTML: Ember-Shell
  def show
    return if performed?
    return render_not_found if feature_disabled?
    render "default/empty"
  end

  # JSON: Türcode prüfen und Session freischalten
  def unlock
    return if performed?
    return render_disabled_json if feature_disabled?

    if params[:website].present?
      # Honeypot: bewusst ohne IP-Logging (Anonymität)
      return render json: { success: false, error: I18n.t("anonymous_feedback.errors.invalid_code") }, status: 403
    end

    door_code = params[:door_code].to_s.strip
    expected  = SiteSetting.anonymous_feedback_door_code.to_s.strip

    if door_code.blank? || expected.blank?
      return render json: { success: false, error: I18n.t("anonymous_feedback.errors.invalid_code") }, status: 403
    end

    # IP wird nur verwendet, um Rate-Limits pro Client zu bauen – aber NIE gespeichert.
    # Wir hashen sie mit secret_key_base, damit weder IP noch Hash ohne Secret rückrechenbar sind.
    ip  = request.remote_ip.to_s
    iph = Digest::SHA256.hexdigest("#{Rails.application.secret_key_base}:#{ip}")
    key = "anon_feedback:doorcode:#{iph}"

    now = Time.now.to_i

    blocked_until = Discourse.redis.hget(key, "blocked_until").to_i
    if blocked_until > now
      wait_s = blocked_until - now
      return render json: { success: false, error: I18n.t("anonymous_feedback.errors.rate_limited", seconds: wait_s) }, status: 429
    end

    last_attempt = Discourse.redis.hget(key, "last_attempt").to_i
    if last_attempt > 0 && (now - last_attempt) < DOORCODE_MIN_INTERVAL
      wait_s = DOORCODE_MIN_INTERVAL - (now - last_attempt)
      return render json: { success: false, error: I18n.t("anonymous_feedback.errors.rate_limited", seconds: wait_s) }, status: 429
    end

    Discourse.redis.hset(key, "last_attempt", now)
    Discourse.redis.expire(key, 86_400)

    ok =
      ActiveSupport::SecurityUtils.secure_compare(
        ::Digest::SHA256.hexdigest(door_code),
        ::Digest::SHA256.hexdigest(expected)
      )

    unless ok
      fails = Discourse.redis.hincrby(key, "fail_count", 1)
      block_seconds = DOORCODE_FAIL_BLOCKS.find { |threshold, _| fails >= threshold }&.last
      Discourse.redis.hset(key, "blocked_until", now + block_seconds) if block_seconds

      # bewusst ohne IP / Hash Logging (Anonymität)
      return render json: { success: false, error: I18n.t("anonymous_feedback.errors.invalid_code") }, status: 403
    end

    Discourse.redis.del(key)
    session[:anon_feedback_unlocked] = true

    render json: { success: true }, status: 200
  end

  # JSON: Feedback senden (PM an Gruppe)
  def create
    return if performed?
    return render_disabled_json if feature_disabled?

    if params[:website].present?
      return render json: { success: false, error: I18n.t("anonymous_feedback.errors.invalid_code") }, status: 403
    end

    unless session[:anon_feedback_unlocked]
      return render json: { success: false, error: I18n.t("anonymous_feedback.errors.not_unlocked") }, status: 403
    end

    enforce_global_rate_limit!

    subject = params[:subject].to_s.strip
    message = params[:message].to_s

    unless subject.present? && message.present?
      return render json: { success: false, error: I18n.t("anonymous_feedback.errors.missing_fields") }, status: 400
    end

    max_len = SiteSetting.anonymous_feedback_max_message_length.to_i
    if max_len > 0 && message.length > max_len
      return render json: { success: false, error: I18n.t("anonymous_feedback.errors.too_long") }, status: 400
    end

    group_name = SiteSetting.anonymous_feedback_target_group.to_s.strip
    if group_name.blank?
      return render json: { success: false, error: I18n.t("anonymous_feedback.errors.group_not_configured") }, status: 500
    end

    group = Group.find_by(name: group_name)
    unless group
      return render json: { success: false, error: I18n.t("anonymous_feedback.errors.group_not_found") }, status: 500
    end

    PostCreator.create!(
      Discourse.system_user,
      title: subject,
      raw: message,
      archetype: Archetype.private_message,
      target_group_names: [group_name]
    )

    # Nach einem erfolgreichen Send muss erneut entsperrt werden (dein gewünschtes Verhalten)
    session.delete(:anon_feedback_unlocked)

    render json: { success: true }, status: 200
  rescue RateLimited => e
    render json: { success: false, error: e.message }, status: 429
  rescue => _e
    # keine Details loggen, um Anonymität zu bewahren
    render json: { success: false, error: I18n.t("anonymous_feedback.errors.send_failed") }, status: 500
  end

  private

  def feature_disabled?
    # 0 = komplett aus (deine Vorgabe)
    SiteSetting.anonymous_feedback_rate_limit_per_hour.to_i <= 0
  end

  def render_disabled_json
    render json: { success: false, error: I18n.t("anonymous_feedback.errors.disabled") }, status: 403
  end

  def enforce_global_rate_limit!
    limit_per_hour = SiteSetting.anonymous_feedback_rate_limit_per_hour.to_i
    return if limit_per_hour <= 0 # wird vorher abgefangen, aber safe

    key = "anon_feedback:global:post:hour"

    count = Discourse.redis.incr(key)
    Discourse.redis.expire(key, 3600) if count == 1

    if count > limit_per_hour
      ttl = Discourse.redis.ttl(key).to_i
      ttl = 3600 if ttl <= 0
      raise RateLimited.new(I18n.t("anonymous_feedback.errors.post_rate_limited", seconds: ttl))
    end
  end

  class RateLimited < StandardError; end
end
