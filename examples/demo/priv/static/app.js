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
    this.defaults = this.parseConfig(this.el.dataset.defaults) || {}

    this.onClick = (event) => {
      const target = event.target instanceof Element ? event.target : null
      if (!target) return

      const reset = target.closest("[data-theme-reset]")
      if (reset && this.el.contains(reset)) {
        event.preventDefault()
        this.resetTheme()
        return
      }

      const button = target.closest("button[data-theme-key]")
      if (button && this.el.contains(button)) {
        event.preventDefault()
        this.applyControl(button)
      }
    }

    this.onChange = (event) => {
      const target = event.target instanceof HTMLInputElement ? event.target : null
      if (!target || !this.el.contains(target)) return
      this.applyControl(target)
    }

    this.onInput = (event) => {
      const target = event.target instanceof HTMLInputElement ? event.target : null
      if (!target || target.type !== "color" || !this.el.contains(target)) return
      this.applyControl(target)
    }

    this.onThemeEvent = () => {
      window.setTimeout(() => this.syncControls(), 0)
    }

    this.onStorage = (event) => {
      if (event.key === THEME_STORAGE_KEY) this.syncControls()
    }

    this.el.addEventListener("click", this.onClick)
    this.el.addEventListener("change", this.onChange)
    this.el.addEventListener("input", this.onInput)
    window.addEventListener("lantern:set-theme", this.onThemeEvent)
    window.addEventListener("storage", this.onStorage)

    this.syncControls()
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick)
    this.el.removeEventListener("change", this.onChange)
    this.el.removeEventListener("input", this.onInput)
    window.removeEventListener("lantern:set-theme", this.onThemeEvent)
    window.removeEventListener("storage", this.onStorage)
  },

  parseConfig(value) {
    try {
      return value ? JSON.parse(value) : null
    } catch (_) {
      return null
    }
  },

  readConfig() {
    try {
      return this.parseConfig(localStorage.getItem(THEME_STORAGE_KEY))
    } catch (_) {
      return null
    }
  },

  applyControl(control) {
    if (control.type === "radio" && !control.checked) return

    const group = control.closest("[data-theme-key]")
    const key = control.dataset.themeKey || group?.dataset.themeKey
    const value = control.dataset.themeValue || control.value
    if (!key || value == null) return

    const config = this.readConfig() || {}
    this.setPath(config, key, value)
    window.dispatchEvent(new CustomEvent("lantern:set-theme", { detail: config }))
  },

  resetTheme() {
    window.dispatchEvent(new CustomEvent("lantern:set-theme", { detail: { reset: true } }))
  },

  setPath(config, key, value) {
    const parts = key.split(".")
    let cursor = config

    for (const part of parts.slice(0, -1)) {
      if (!cursor[part] || typeof cursor[part] !== "object" || Array.isArray(cursor[part])) {
        cursor[part] = {}
      }
      cursor = cursor[part]
    }

    cursor[parts[parts.length - 1]] = value
  },

  getPath(config, key) {
    return key.split(".").reduce((value, part) => value?.[part], config)
  },

  currentValue(key) {
    const stored = this.readConfig() || {}
    const storedValue = this.getPath(stored, key)
    if (storedValue !== undefined && storedValue !== null) return storedValue
    return this.getPath(this.defaults, key)
  },

  syncControls() {
    this.el.querySelectorAll("button[data-theme-key]").forEach((button) => {
      const selected = button.dataset.themeValue === this.currentValue(button.dataset.themeKey)
      button.classList.toggle("docs-swatch-selected", selected)
      button.setAttribute("aria-pressed", selected ? "true" : "false")
    })

    this.el.querySelectorAll("input[type='radio']").forEach((input) => {
      const group = input.closest("[data-theme-key]")
      const key = input.dataset.themeKey || group?.dataset.themeKey
      if (!key) return

      input.dataset.themeKey = key
      input.dataset.themeValue = input.dataset.themeValue || input.value
      input.checked = input.dataset.themeValue === this.currentValue(key)
    })

    this.el.querySelectorAll("input[type='color'][data-theme-key]").forEach((input) => {
      const value = this.currentValue(input.dataset.themeKey)
      if (/^#[0-9a-f]{6}$/i.test(value)) input.value = value
    })
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: { ...LanternUIHooks, LanternGrid, LiveCode, TurnstileWidget, DemoTheming },
  params: { _csrf_token: csrfToken },
})

liveSocket.connect()
window.liveSocket = liveSocket
