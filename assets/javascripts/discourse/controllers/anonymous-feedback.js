import Controller from "@ember/controller";
import I18n from "discourse-i18n";

export default class AnonymousFeedbackController extends Controller {
  get title() {
    return I18n.t("js.anonymous_feedback.title_af");
  }

  get intro() {
    return I18n.t("js.anonymous_feedback.intro");
  }

  get subjectPlaceholder() {
    return this.siteSettings.anonymous_feedback_subject_placeholder;
  }

  get messagePlaceholder() {
    return this.siteSettings.anonymous_feedback_message_placeholder;
  }
}
