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
    this.presets = this.parseConfig(this.el.dataset.presets) || {}
    this.tokenMode = "light"

    this.onClick = (event) => {
      const target = event.target instanceof Element ? event.target : null
      if (!target) return

      const reset = target.closest("[data-theme-reset]")
      if (reset && this.el.contains(reset)) {
        event.preventDefault()
        this.resetTheme()
        return
      }

      const modeTab = target.closest("[data-theme-mode-tab], [data-theme-mode-tabs] .lui-tab")
      if (modeTab && this.el.contains(modeTab)) {
        event.preventDefault()
        this.setTokenMode(
          modeTab.dataset.themeModeTab || modeTab.getAttribute("phx-value-tab") || "light"
        )
        return
      }

      const preset = target.closest("[data-theme-preset]")
      if (preset && this.el.contains(preset)) {
        event.preventDefault()
        this.applyPreset(preset)
        return
      }

      const button = target.closest("button[data-theme-key]")
      if (button && this.el.contains(button)) {
        event.preventDefault()
        this.applyControl(button)
      }
    }

    this.onChange = (event) => {
      const target =
        event.target instanceof HTMLInputElement || event.target instanceof HTMLSelectElement
          ? event.target
          : null
      if (!target || !this.el.contains(target)) return

      if (target.dataset.themeToken) {
        this.applyTokenInput(target)
        return
      }

      this.applyControl(target)
    }

    this.onInput = (event) => {
      const target = event.target instanceof HTMLInputElement ? event.target : null
      if (!target || target.type !== "color" || !this.el.contains(target)) return

      if (target.dataset.themeToken) {
        this.applyTokenInput(target)
        return
      }

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
    if (key === "font") {
      config.light = { ...(config.light || {}), font: value }
      config.dark = { ...(config.dark || {}), font: value }
    } else {
      this.setPath(config, key, value)
    }
    window.dispatchEvent(new CustomEvent("lantern:set-theme", { detail: config }))
  },

  applyPreset(control) {
    const presetKey = control.dataset.themePreset
    const [mode] = presetKey.split(":")
    const preset = this.presets[presetKey]
    if (!mode || !preset) return

    const config = this.readConfig() || {}
    config[mode] = this.clone(preset)
    window.dispatchEvent(new CustomEvent("lantern:set-theme", { detail: config }))
  },

  applyTokenInput(input) {
    const mode = input.dataset.themeMode || this.tokenMode || "light"
    const token = input.dataset.themeToken
    const value = input.value
    if (!token || !/^#[0-9a-f]{6}$/i.test(value)) return

    const config = this.readConfig() || {}
    config[mode] = { ...(this.defaults[mode] || {}), ...(config[mode] || {}), [token]: value }
    window.dispatchEvent(new CustomEvent("lantern:set-theme", { detail: config }))
  },

  resetTheme() {
    window.dispatchEvent(new CustomEvent("lantern:set-theme", { detail: { reset: true } }))
  },

  setTokenMode(mode) {
    this.tokenMode = mode === "dark" ? "dark" : "light"
    this.syncTokenMode()
    this.syncTokenInputs()
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

  clone(value) {
    return JSON.parse(JSON.stringify(value || {}))
  },

  deepMerge(base, extra) {
    const merged = this.clone(base)
    for (const [key, value] of Object.entries(extra || {})) {
      if (
        value &&
        typeof value === "object" &&
        !Array.isArray(value) &&
        merged[key] &&
        typeof merged[key] === "object" &&
        !Array.isArray(merged[key])
      ) {
        merged[key] = this.deepMerge(merged[key], value)
      } else {
        merged[key] = this.clone(value)
      }
    }
    return merged
  },

  getPath(config, key) {
    return key.split(".").reduce((value, part) => value?.[part], config)
  },

  effectiveConfig() {
    return this.deepMerge(this.defaults, this.readConfig() || {})
  },

  currentValue(key, effective = this.effectiveConfig()) {
    if (key === "font") {
      return effective.light?.font || effective.dark?.font || effective.font
    }

    const storedValue = this.getPath(effective, key)
    if (storedValue !== undefined && storedValue !== null) return storedValue
    return this.getPath(this.defaults, key)
  },

  sorted(value) {
    if (Array.isArray(value)) return value.map((item) => this.sorted(item))
    if (!value || typeof value !== "object") return value

    return Object.keys(value)
      .sort()
      .reduce((acc, key) => {
        acc[key] = this.sorted(value[key])
        return acc
      }, {})
  },

  deepEqual(a, b) {
    return JSON.stringify(this.sorted(a || {})) === JSON.stringify(this.sorted(b || {}))
  },

  syncControls() {
    const stored = this.readConfig() || {}
    const effective = this.effectiveConfig()

    this.el.querySelectorAll("button[data-theme-key]").forEach((button) => {
      const selected =
        button.dataset.themeValue === this.currentValue(button.dataset.themeKey, effective)
      button.classList.toggle("docs-swatch-selected", selected)
      button.setAttribute("aria-pressed", selected ? "true" : "false")
    })

    this.el.querySelectorAll("[data-theme-preset]").forEach((button) => {
      const presetKey = button.dataset.themePreset
      const [mode] = presetKey.split(":")
      const current = stored[mode] || this.defaults[mode] || {}
      const selected = this.deepEqual(current, this.presets[presetKey])
      button.classList.toggle("docs-theme-card-selected", selected)
      button.setAttribute("aria-pressed", selected ? "true" : "false")
    })

    this.el.querySelectorAll("input[type='radio']").forEach((input) => {
      const group = input.closest("[data-theme-key]")
      const key = input.dataset.themeKey || group?.dataset.themeKey
      if (!key) return

      input.dataset.themeKey = key
      input.dataset.themeValue = input.dataset.themeValue || input.value
      input.checked = input.dataset.themeValue === this.currentValue(key, effective)
    })

    this.el.querySelectorAll("input[type='color'][data-theme-key]").forEach((input) => {
      const value = this.currentValue(input.dataset.themeKey, effective)
      if (/^#[0-9a-f]{6}$/i.test(value)) input.value = value
    })

    this.syncTokenMode()
    this.syncTokenInputs()
  },

  syncTokenMode() {
    this.el.querySelectorAll("[data-theme-token-panel]").forEach((panel) => {
      panel.hidden = panel.dataset.themeTokenPanel !== this.tokenMode
    })

    this.el.querySelectorAll("[data-theme-mode-tabs] .lui-tab").forEach((tab) => {
      const mode = tab.dataset.themeModeTab || tab.getAttribute("phx-value-tab")
      const selected = mode === this.tokenMode
      tab.classList.toggle("lui-tab-active", selected)
      tab.setAttribute("aria-selected", selected ? "true" : "false")
    })
  },

  syncTokenInputs() {
    this.el.querySelectorAll("input[type='color'][data-theme-token]").forEach((input) => {
      const mode = input.dataset.themeMode || this.tokenMode || "light"
      const token = input.dataset.themeToken
      const value = this.resolvedTokenHex(token, mode)
      if (!value) return

      input.value = value
      const valueEl = this.el.querySelector(
        `[data-theme-mode="${mode}"][data-theme-token-value="${token}"]`
      )
      if (valueEl) valueEl.textContent = value
    })
  },

  resolvedTokenHex(token, mode) {
    if (!this.colorProbe) {
      this.colorProbe = document.createElement("div")
      this.colorProbe.setAttribute("aria-hidden", "true")
      document.body.appendChild(this.colorProbe)
    }

    const cssToken = token.replace(/_/g, "-")
    this.colorProbe.className = mode === "dark" ? "dark" : "light"
    this.colorProbe.style.cssText =
      "position:fixed;left:-9999px;top:-9999px;width:1px;height:1px;" +
      `visibility:hidden;pointer-events:none;background:var(--lantern-${cssToken});`

    const styles = getComputedStyle(this.colorProbe)
    return (
      this.colorToHex(styles.backgroundColor) ||
      this.colorToHex(styles.getPropertyValue(`--lantern-${cssToken}`).trim()) ||
      "#000000"
    )
  },

  colorToHex(value) {
    if (!value) return null

    const hex = value.trim().match(/^#([0-9a-f]{3}|[0-9a-f]{6})$/i)
    if (hex) {
      const raw = hex[1]
      if (raw.length === 6) return `#${raw.toLowerCase()}`
      return `#${raw.split("").map((char) => char + char).join("").toLowerCase()}`
    }

    const rgb = this.parseRgb(value) || this.parseSrgb(value) || this.canvasColorToHex(value)
    return rgb ? this.rgbToHex(rgb[0], rgb[1], rgb[2]) : null
  },

  parseRgb(value) {
    const match = value.trim().match(/^rgba?\((.+)\)$/i)
    if (!match) return null

    const channels = match[1]
      .replace(/,/g, " ")
      .replace(/\s*\/\s*[\d.]+%?\s*$/, "")
      .trim()
      .split(/\s+/)
      .slice(0, 3)
      .map((part) => (part.endsWith("%") ? parseFloat(part) * 2.55 : parseFloat(part)))

    return channels.length === 3 && channels.every(Number.isFinite) ? channels : null
  },

  parseSrgb(value) {
    const match = value.trim().match(/^color\(\s*srgb\s+(.+)\)$/i)
    if (!match) return null

    const channels = match[1]
      .replace(/\s*\/\s*[\d.]+%?\s*$/, "")
      .trim()
      .split(/\s+/)
      .slice(0, 3)
      .map((part) => parseFloat(part) * 255)

    return channels.length === 3 && channels.every(Number.isFinite) ? channels : null
  },

  canvasColorToHex(value) {
    if (!this.colorCanvas) {
      this.colorCanvas = document.createElement("canvas")
      this.colorCanvas.width = 1
      this.colorCanvas.height = 1
    }

    const context = this.colorCanvas.getContext("2d", { willReadFrequently: true })
    if (!context) return null

    context.clearRect(0, 0, 1, 1)
    context.fillStyle = "#010203"
    context.fillStyle = value
    if (context.fillStyle === "#010203" && value.trim().toLowerCase() !== "#010203") return null
    context.fillRect(0, 0, 1, 1)

    const data = context.getImageData(0, 0, 1, 1).data
    return data[3] === 0 ? null : [data[0], data[1], data[2]]
  },

  rgbToHex(r, g, b) {
    return (
      "#" +
      [r, g, b]
        .map((channel) => Math.round(Math.min(255, Math.max(0, channel))).toString(16).padStart(2, "0"))
        .join("")
    )
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: { ...LanternUIHooks, LanternGrid, LiveCode, TurnstileWidget, DemoTheming },
  params: { _csrf_token: csrfToken },
})

liveSocket.connect()
window.liveSocket = liveSocket
