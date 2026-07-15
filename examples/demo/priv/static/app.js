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

const DocsExample = {
  mounted() {
    this.active = "preview"
    this.el.addEventListener("click", (e) => {
      const tab = e.target.closest("[data-tab]")
      if (!tab) return
      this.active = tab.dataset.tab
      this.apply()
    })
    this.apply()
  },
  apply() {
    this.el.querySelectorAll("[data-tab]").forEach((t) =>
      t.setAttribute("aria-selected", String(t.dataset.tab === this.active))
    )
    this.el.querySelectorAll("[data-panel]").forEach((p) => {
      p.hidden = p.dataset.panel !== this.active
    })
  },
  updated() {
    this.apply()
  },
}

const DemoChrome = {
  // Client-side theme + density toggles for the whole demo shell. State lives
  // in localStorage and is re-applied after every LiveView patch (morphdom
  // strips client-set classes/attrs), so the toggles work uniformly on every
  // page and persist across navigation — like a real app's appearance settings.
  shell() {
    return document.getElementById(this.el.dataset.shell)
  },

  restore() {
    try {
      this.state = JSON.parse(localStorage.getItem("lui-demo-chrome") || "null")
    } catch (_) {
      this.state = null
    }
    if (!this.state) {
      const dark = window.matchMedia("(prefers-color-scheme: dark)").matches
      this.state = { theme: dark ? "dark" : "light", density: "compact" }
    }
  },

  apply() {
    const shell = this.shell()
    if (shell) {
      shell.classList.toggle("dark", this.state.theme === "dark")
      shell.classList.toggle("light", this.state.theme === "light")
      shell.setAttribute("data-lantern-density", this.state.density)
    }
    const t = this.el.querySelector('[data-part="theme-label"]')
    if (t) t.textContent = this.state.theme === "dark" ? "Light" : "Dark"
    const d = this.el.querySelector('[data-part="density-label"]')
    if (d) d.textContent = this.state.density === "compact" ? "Compact" : "Comfortable"
  },

  save() {
    try {
      localStorage.setItem("lui-demo-chrome", JSON.stringify(this.state))
    } catch (_) {}
  },

  mounted() {
    this.restore()
    this.apply()
    this.el.addEventListener("click", (e) => {
      if (e.target.closest('[data-part="theme-toggle"]')) {
        this.state.theme = this.state.theme === "dark" ? "light" : "dark"
        this.save()
        this.apply()
      } else if (e.target.closest('[data-part="density-toggle"]')) {
        this.state.density = this.state.density === "compact" ? "comfortable" : "compact"
        this.save()
        this.apply()
      }
    })
  },

  updated() {
    this.apply()
  },
}

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
  hooks: { ...LanternUIHooks, LanternGrid, LiveCode, TurnstileWidget, DemoTheming, DemoChrome, DocsExample },
  params: { _csrf_token: csrfToken },
})

liveSocket.connect()
window.liveSocket = liveSocket
