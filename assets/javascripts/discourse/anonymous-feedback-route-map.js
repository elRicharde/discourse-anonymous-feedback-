import { apiInitializer } from "discourse/lib/api";

export default apiInitializer("1.8.0", (api) => {
  // Public pages
  api.addRoute("anonymous-feedback", { path: "/anonymous-feedback" });
  api.addRoute("white-board", { path: "/white-board" });
});
