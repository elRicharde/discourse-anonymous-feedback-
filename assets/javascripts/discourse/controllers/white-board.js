import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import I18n from "discourse-i18n";

export default class WhiteBoardController extends Controller {
  @tracked unlocked = false;
  @tracked sending = false;
  @tracked sent = false;
  @tracked error = null;

  @tracked doorCode = "";
  @tracked subject = "";
  @tracked message = "";

  // honeypot
  @tracked website = "";

  get title() {
    return I18n.t("js.anonymous_feedback.title_wb");
  }

  get intro() {
    return I18n.t("js.anonymous_feedback.intro");
  }

  @action
  async unlock() {
    this.error = null;
    this.sent = false;

    const code = (this.doorCode || "").trim();
    if (!code) {
      this.error = I18n.t("js.anonymous_feedback.errors.invalid_code");
      return;
    }

    try {
      await ajax("/white-board/unlock", {
        type: "POST",
        data: {
          door_code: code,
          website: this.website,
        },
      });

      this.unlocked = true;
      this.subject = "";
      this.message = "";
      this.website = "";
    } catch (e) {
      this.error =
        e?.jqXHR?.responseJSON?.error ||
        I18n.t("js.anonymous_feedback.errors.generic");
    }
  }

  @action
  async send() {
    this.error = null;
    this.sent = false;

    const subject = (this.subject || "").trim();
    const message = (this.message || "").trim();

    if (!subject || !message) {
      this.error = I18n.t("js.anonymous_feedback.errors.missing_fields");
      return;
    }

    this.sending = true;
    try {
      await ajax("/white-board", {
        type: "POST",
        data: {
          subject,
          message,
          website: this.website,
        },
      });

      this.sent = true;
      this.unlocked = false;
      this.doorCode = "";
      this.subject = "";
      this.message = "";
      this.website = "";
    } catch (e) {
      this.error =
        e?.jqXHR?.responseJSON?.error ||
        I18n.t("js.anonymous_feedback.errors.generic");
    } finally {
      this.sending = false;
    }
  }
}
