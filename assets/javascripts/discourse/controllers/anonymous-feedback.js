import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import I18n from "I18n";

export default class AnonymousFeedbackController extends Controller {
  @tracked unlocked = false;
  @tracked sending = false;
  @tracked sent = false;

  @tracked doorCode = "";
  @tracked subject = "";
  @tracked message = "";

  @tracked error = null;

  // honeypot
  @tracked website = "";

  @action
  async unlock() {
    this.error = null;
    this.sent = false;

    const door = (this.doorCode || "").trim();
    if (!door) {
      this.error = I18n.t("anonymous_feedback.errors.invalid_code");
      return;
    }

    try {
      await ajax("/anonymous-feedback/unlock", {
        type: "POST",
        data: { door_code: door, website: this.website },
      });

      this.unlocked = true;
      this.error = null;
    } catch (e) {
      this.error =
        e?.jqXHR?.responseJSON?.error ||
        I18n.t("anonymous_feedback.errors.generic");
    }
  }

  @action
  async send() {
    this.error = null;
    this.sent = false;

    const subject = (this.subject || "").trim();
    const message = this.message || "";

    if (!subject || !message) {
      this.error = I18n.t("anonymous_feedback.errors.missing_fields");
      return;
    }

    this.sending = true;
    try {
      await ajax("/anonymous-feedback", {
        type: "POST",
        data: { subject, message, website: this.website },
      });

      this.sent = true;

      // zurück zur Doorcode-Seite (wie du es willst)
      this.unlocked = false;
      this.doorCode = "";
      this.subject = "";
      this.message = "";
    } catch (e) {
      this.error =
        e?.jqXHR?.responseJSON?.error ||
        I18n.t("anonymous_feedback.errors.generic");
    } finally {
      this.sending = false;
    }
  }
}
