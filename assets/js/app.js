// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
import { applyChatTranscriptTimes } from "./chat_transcript_time.mjs"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken}
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Account page: tab buttons swap notification center vs settings (no full navigation).
document.addEventListener("DOMContentLoaded", () => {
  const accountRoot = document.getElementById("account-page")
  if (accountRoot) {
    const tabs = accountRoot.querySelectorAll("[data-account-tab]")
    const panels = accountRoot.querySelectorAll("[data-account-panel]")
    tabs.forEach((btn) => {
      btn.addEventListener("click", () => {
        const key = btn.getAttribute("data-account-tab")
        tabs.forEach((t) => {
          const on = t.getAttribute("data-account-tab") === key
          t.setAttribute("aria-selected", on ? "true" : "false")
        })
        panels.forEach((p) => {
          const show = p.getAttribute("data-account-panel") === key
          p.hidden = !show
        })
      })
    })
  }
})

// Local `<time data-local-chat-time>` labels from `datetime` (UTC ISO); chat Enter sends, Shift+Enter newline.
document.addEventListener("DOMContentLoaded", () => {
  applyChatTranscriptTimes()

  const messageBody = document.getElementById("message_body")
  if (!messageBody?.form) return

  messageBody.addEventListener("keydown", (e) => {
    if (e.key !== "Enter" || e.shiftKey) return
    e.preventDefault()
    messageBody.form.requestSubmit()
  })
})

