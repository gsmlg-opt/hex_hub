// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
import { register as registerAlert } from "@duskmoon-dev/elements/el-alert"
import { register as registerBreadcrumbs } from "@duskmoon-dev/elements/el-breadcrumbs"
import { register as registerButton } from "@duskmoon-dev/elements/el-button"
import { register as registerDialog } from "@duskmoon-dev/elements/el-dialog"
import { register as registerPagination } from "@duskmoon-dev/elements/el-pagination"
import { installDuskmoonConfirmDialogBridge } from "./duskmoon_confirm_bridge.js"

// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import * as DuskmoonHooks from "phoenix_duskmoon/hooks";

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/admin/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: { ...DuskmoonHooks },
})

registerAlert()
registerBreadcrumbs()
registerButton()
registerDialog()
registerPagination()
installDuskmoonConfirmDialogBridge()

// Vanilla JS theme switcher for non-LiveView pages (where phx-hook won't fire)
document.addEventListener("change", (e) => {
  if (e.target.classList.contains("theme-controller-item")) {
    const theme = e.target.value;
    if (theme && theme !== "default") {
      document.documentElement.setAttribute("data-theme", theme);
    } else {
      document.documentElement.removeAttribute("data-theme");
    }
    localStorage.setItem("theme", theme);
    const details = e.target.closest("details");
    if (details) details.removeAttribute("open");
  }
});

const savedTheme = localStorage.getItem("theme") || "default";
document.querySelectorAll(".theme-controller-item").forEach((input) => {
  input.checked = input.value === savedTheme;
});

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enable for 1s delays
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
