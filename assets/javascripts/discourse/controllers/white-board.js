import Controller from "@ember/controller";
import I18n from "discourse-i18n";

export default class WhiteBoardController extends Controller {
  get title() {
    return I18n.t("js.anonymous_feedback.title_wb");
  }

  get intro() {
    return I18n.t("js.anonymous_feedback.intro");
  }

  get subjectPlaceholder() {
    return this.siteSettings.white_board_subject_placeholder;
  }

  get messagePlaceholder() {
    return this.siteSettings.white_board_message_placeholder;
  }
}
