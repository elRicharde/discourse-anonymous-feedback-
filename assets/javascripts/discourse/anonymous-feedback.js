import { ajax } from "discourse/lib/ajax";
import { apiInitializer } from "discourse/lib/api";

function bindAnonymousFeedback() {
  const btn = document.getElementById("af_unlock_btn");
  const input = document.getElementById("af_door_code");
  const errorBox = document.getElementById("af_error");

  if (!btn || !input) {
    // Seite ist (noch) nicht unsere
    return;
  }

  btn.addEventListener("click", () => {
    ajax("/anonymous-feedback/unlock", {
      type: "POST",
      data: { door_code: input.value }
    })
      .then(() => {
        window.location.reload();
      })
      .catch((e) => {
        if (errorBox) {
          errorBox.innerText =
            e?.jqXHR?.responseJSON?.error || "Fehler";
          errorBox.style.display = "block";
        }
      });
  });
}

export default apiInitializer("0.8", (api) => {
  api.onPageChange(() => {
    bindAnonymousFeedback();
  });
});
