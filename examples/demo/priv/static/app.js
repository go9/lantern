import { Socket } from "https://cdn.jsdelivr.net/npm/phoenix@1.8.7/+esm"
import { LiveSocket } from "/js/phoenix_live_view.esm.js"
import { LanternGrid } from "/lantern/hooks.js"
import { LiveCode } from "/livecode/livecode.js"
import LanternUIHooks from "/lantern_ui_hooks.js"

const TurnstileWidget = {
  mounted() {
    const sitekey = this.el.dataset.sitekey
    const hook = this

    const render = () => {
      if (window.turnstile) {
        window.turnstile.render(this.el, {
          sitekey,
          callback: (token) => hook.pushEvent("sandbox_token", { token }),
        })
      } else {
        // Script not ready yet — retry
        setTimeout(render, 100)
      }
    }

    render()
  },
}

const THEME_STORAGE_KEY = "lui-theme"

const DemoTheming = {
  mounted() {
    // Inject the active theme CSS the server pushes, and persist / restore the
    // active light+dark theme ids to localStorage (client-side stand-in for
    // flicker's DB-backed themes).
    this.styleEl = document.getElementById("lui-demo-theme-css")
    if (!this.styleEl) {
      this.styleEl = document.createElement("style")
      this.styleEl.id = "lui-demo-theme-css"
      document.head.appendChild(this.styleEl)
    }

    this.handleEvent("demo:inject-theme", ({ css }) => {
      this.styleEl.textContent = css
    })
    this.handleEvent("demo:persist-theme", (ids) => {
      try {
        localStorage.setItem("lui-demo-theme", JSON.stringify(ids))
      } catch (_) {}
    })

    let stored = null
    try {
      stored = JSON.parse(localStorage.getItem("lui-demo-theme") || "null")
    } catch (_) {}
    this.pushEvent("restore", stored || {})
  },

  destroyed() {
    // Leave the injected theme in place across navigations within the demo.
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: { ...LanternUIHooks, LanternGrid, LiveCode, TurnstileWidget, DemoTheming },
  params: { _csrf_token: csrfToken },
})

liveSocket.connect()
window.liveSocket = liveSocket
