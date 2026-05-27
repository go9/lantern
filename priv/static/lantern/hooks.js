// Lantern LiveView hook — column resizing, "set NULL" field clearing, and live
// JSON validation. Register it on your LiveSocket:
//
//   import { LanternGrid } from "lantern/hooks"
//   const liveSocket = new LiveSocket("/live", Socket, {
//     hooks: { LanternGrid },
//     params: { _csrf_token: csrfToken },
//   })
//
// (Resolve "lantern/hooks" however your bundler reaches the dep's
// priv/static/lantern/hooks.js — see the README for esbuild/Vite examples.)

export const LanternGrid = {
  mounted() {
    this.widths = {}
    this.table = this.el.dataset.table
    this._dragMove = null
    this._dragUp = null

    // Drag a column's right edge to resize. Widths persist across re-renders.
    this.el.addEventListener("pointerdown", (e) => {
      const handle = e.target.closest(".lt-resize")
      if (!handle) return
      e.preventDefault()
      const th = handle.closest("th")
      const col = handle.dataset.col
      const startX = e.clientX
      const startW = th.offsetWidth

      const setWidth = (el, w) => {
        el.style.width = el.style.minWidth = el.style.maxWidth = w + "px"
      }
      // Stored on `this` so destroyed() can clean up if the component is
      // patched out (e.g. user hits Esc) mid-drag — otherwise the window
      // listeners stick around forever.
      this._dragMove = (ev) => {
        const w = Math.max(48, startW + (ev.clientX - startX))
        setWidth(th, w)
        this.widths[col] = w
      }
      this._dragUp = () => {
        window.removeEventListener("pointermove", this._dragMove)
        window.removeEventListener("pointerup", this._dragUp)
        window.removeEventListener("pointercancel", this._dragUp)
        this._dragMove = null
        this._dragUp = null
      }
      window.addEventListener("pointermove", this._dragMove)
      window.addEventListener("pointerup", this._dragUp)
      // Touch drags can end via pointercancel (browser took over the gesture).
      window.addEventListener("pointercancel", this._dragUp)
    })

    // "∅" buttons clear their field so it saves as SQL NULL.
    this.el.addEventListener("click", (e) => {
      const nullBtn = e.target.closest(".lt-null")
      if (!nullBtn) return
      e.preventDefault()
      const ctrl = nullBtn.parentElement.querySelector("input, textarea, select")
      if (ctrl) {
        ctrl.value = ""
        ctrl.dispatchEvent(new Event("input", { bubbles: true }))
      }
    })

    // Flag invalid JSON in json/jsonb fields as the user types (empty = NULL = ok).
    this.el.addEventListener("input", (e) => {
      const ta = e.target.closest(".lt-json")
      if (!ta) return
      let ok = true
      if (ta.value.trim() !== "") {
        try {
          JSON.parse(ta.value)
        } catch {
          ok = false
        }
      }
      ta.classList.toggle("lt-invalid", !ok)
    })
  },

  updated() {
    // Drop stored widths when the user navigates to a different table — the
    // column names are different, so the old values are meaningless and would
    // grow unbounded across many table switches.
    const table = this.el.dataset.table
    if (table !== this.table) {
      this.widths = {}
      this.table = table
      return
    }

    for (const col in this.widths) {
      const th = this.el.querySelector(`th[data-col="${CSS.escape(col)}"]`)
      if (th) {
        const w = this.widths[col] + "px"
        th.style.width = th.style.minWidth = th.style.maxWidth = w
      }
    }
  },

  destroyed() {
    if (this._dragMove) window.removeEventListener("pointermove", this._dragMove)
    if (this._dragUp) {
      window.removeEventListener("pointerup", this._dragUp)
      window.removeEventListener("pointercancel", this._dragUp)
    }
    this._dragMove = null
    this._dragUp = null
  },
}

export default { LanternGrid }
