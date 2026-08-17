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

// Admin page: tab panels for auction sources / jobs / candidates.
document.addEventListener("DOMContentLoaded", () => {
  const adminRoot = document.getElementById("admin-page")
  if (adminRoot) {
    const tabs = adminRoot.querySelectorAll("[data-admin-tab]")
    const panels = adminRoot.querySelectorAll("[data-admin-panel]")
    tabs.forEach((btn) => {
      btn.addEventListener("click", () => {
        const key = btn.getAttribute("data-admin-tab")
        tabs.forEach((t) => {
          const on = t.getAttribute("data-admin-tab") === key
          t.setAttribute("aria-selected", on ? "true" : "false")
        })
        panels.forEach((p) => {
          const show = p.getAttribute("data-admin-panel") === key
          p.hidden = !show
        })
        const url = new URL(window.location.href)
        url.searchParams.set("tab", key)
        window.history.replaceState({}, "", url)
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

// #region agent log
function agentDbg(hypothesisId, location, message, data) {
  fetch("http://127.0.0.1:7308/ingest/d4d32ca2-9b81-4ee5-a553-7fee94b1b422", {
    method: "POST",
    headers: {"Content-Type": "application/json", "X-Debug-Session-Id": "4bc2bf"},
    body: JSON.stringify({
      sessionId: "4bc2bf",
      runId: "pre-fix",
      hypothesisId,
      location,
      message,
      data,
      timestamp: Date.now()
    })
  }).catch(() => {})
}

function agentCs(el, prop) {
  return el ? window.getComputedStyle(el)[prop] : null
}

function agentLayoutSnapshot() {
  const html = document.documentElement
  const body = document.body
  const main = document.querySelector("main")
  const logo = document.querySelector("header img")
  const dialogs = Array.from(document.querySelectorAll('[role="dialog"]')).map((d) => ({
    id: d.id,
    hidden: d.hidden,
    className: String(d.className || ""),
    overflowY: agentCs(d, "overflowY"),
    position: agentCs(d, "position"),
    scrollHeight: d.scrollHeight,
    clientHeight: d.clientHeight
  }))
  return {
    path: location.pathname + location.search,
    innerWidth: window.innerWidth,
    innerHeight: window.innerHeight,
    htmlOverflowY: agentCs(html, "overflowY"),
    htmlTouchAction: agentCs(html, "touchAction"),
    htmlScrollHeight: html.scrollHeight,
    htmlClientHeight: html.clientHeight,
    bodyOverflowInline: body.style.overflow,
    bodyOverflowY: agentCs(body, "overflowY"),
    bodyTouchAction: agentCs(body, "touchAction"),
    bodyScrollHeight: body.scrollHeight,
    docCanScrollY: html.scrollHeight > window.innerHeight + 8,
    mainOverflowY: main ? agentCs(main, "overflowY") : null,
    mainScrollHeight: main ? main.scrollHeight : null,
    logoWidth: logo ? Math.round(logo.getBoundingClientRect().width) : null,
    logoOverflowsViewport: logo ? logo.getBoundingClientRect().width > window.innerWidth : null,
    dialogs
  }
}

function agentModalSnapshot(modal) {
  if (!modal) return null
  const overlay =
    modal.querySelector("[data-disclaimer-modal-overlay], [data-chat-disclaimer-modal-overlay]")
  const panel = overlay ? overlay.nextElementSibling : modal.children[1]
  const overlayCs = overlay ? window.getComputedStyle(overlay) : null
  const panelCs = panel ? window.getComputedStyle(panel) : null
  const panelBox = panel ? panel.getBoundingClientRect() : null
  return {
    id: modal.id,
    hidden: modal.hidden,
    className: String(modal.className || ""),
    modalOverflowY: agentCs(modal, "overflowY"),
    modalPosition: agentCs(modal, "position"),
    modalScrollHeight: modal.scrollHeight,
    modalClientHeight: modal.clientHeight,
    bodyOverflowInline: document.body.style.overflow,
    panelHeight: panelBox ? Math.round(panelBox.height) : null,
    panelTop: panelBox ? Math.round(panelBox.top) : null,
    panelBottom: panelBox ? Math.round(panelBox.bottom) : null,
    panelOverflowY: panelCs ? panelCs.overflowY : null,
    panelMaxHeight: panelCs ? panelCs.maxHeight : null,
    overlayPointerEvents: overlayCs ? overlayCs.pointerEvents : null,
    overlayZ: overlayCs ? overlayCs.zIndex : null,
    panelZ: panelCs ? panelCs.zIndex : null,
    viewportH: window.innerHeight,
    panelOverflowsViewport: panelBox ? panelBox.bottom > window.innerHeight : null,
    modalCanScroll: modal.scrollHeight > modal.clientHeight + 8
  }
}

document.addEventListener("DOMContentLoaded", () => {
  agentDbg("C", "app.js:DOMContentLoaded", "page layout snapshot", agentLayoutSnapshot())

  document.querySelectorAll('[role="dialog"]').forEach((modal) => {
    const obs = new MutationObserver(() => {
      if (!modal.hidden) {
        agentDbg("A", "app.js:modal-open", "disclaimer modal opened", agentModalSnapshot(modal))
      }
    })
    obs.observe(modal, {attributes: true, attributeFilter: ["hidden", "class", "style"]})
  })

  let touchLogged = false
  document.addEventListener(
    "touchmove",
    (e) => {
      const openModal = document.querySelector('[role="dialog"]:not([hidden])')
      if (!openModal || touchLogged) return
      touchLogged = true
      const target = e.target
      agentDbg("B", "app.js:touchmove", "touchmove while disclaimer modal open", {
        targetId: target && target.id,
        targetClass: target && String(target.className || ""),
        inOverlay: !!(target && target.closest && target.closest("[data-disclaimer-modal-overlay], [data-chat-disclaimer-modal-overlay]")),
        inPanel: !!(target && target.closest && openModal.contains(target) && !target.closest("[data-disclaimer-modal-overlay], [data-chat-disclaimer-modal-overlay]")),
        cancelable: e.cancelable,
        defaultPrevented: e.defaultPrevented,
        modal: agentModalSnapshot(openModal)
      })
    },
    {passive: true}
  )

  let scrollLogged = false
  window.addEventListener(
    "scroll",
    () => {
      if (scrollLogged) return
      scrollLogged = true
      agentDbg("C", "app.js:window-scroll", "window scrolled", {
        scrollY: window.scrollY,
        path: location.pathname + location.search,
        openModalId: (document.querySelector('[role="dialog"]:not([hidden])') || {}).id || null
      })
    },
    {passive: true}
  )
})
// #endregion

