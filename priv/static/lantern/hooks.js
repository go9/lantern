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
    this.storageKey = `lantern:${this.el.id}:sql-state`

    try {
      const stored = JSON.parse(localStorage.getItem(this.storageKey) || "{}")
      this.pushEventTo(this.el, "restore_sql_state", {
        saved_queries: stored.saved_queries || [],
        sql_history: stored.sql_history || [],
      })
    } catch {}

    this.handleEvent("lantern:persist-sql-state", ({ saved_queries, sql_history }) => {
      localStorage.setItem(this.storageKey, JSON.stringify({ saved_queries, sql_history }))
    })

    this.handleEvent("lantern:download", ({ filename, mime, content }) => {
      const blob = new Blob([content], { type: mime })
      const url = URL.createObjectURL(blob)
      const a = document.createElement("a")
      a.href = url
      a.download = filename
      document.body.appendChild(a)
      a.click()
      a.remove()
      URL.revokeObjectURL(url)
    })

    this.handleEvent("lantern:copy", ({ content }) => {
      if (navigator.clipboard) navigator.clipboard.writeText(content)
    })

    this.el.addEventListener("keydown", (e) => {
      const editor = e.target.closest(".lt-sql-editor")
      if (!editor) return
      if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
        e.preventDefault()
        this.el.querySelector(`#${CSS.escape(this.el.id)}-run-sql`)?.click()
      }
    })

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

    // Value peek: left-click a (CSS-truncated) data cell to see its full value
    // in a small popover, pretty-printed for json/jsonb. The cell's textContent
    // is always the full, un-truncated value, so we read it straight off.
    this._cellPeekEl = null
    this.el.addEventListener("click", (e) => {
      const cell = e.target.closest(".lt-td")
      if (!cell || !this.el.contains(cell)) return
      // Don't hijack clicks on interactive children (FK links, edit buttons,
      // inputs, the resize handle) — those have their own behavior.
      if (e.target.closest("button, a, input, select, label, .lt-resize")) return
      // Don't fire while the user is selecting text inside the cell.
      const sel = window.getSelection && window.getSelection()
      if (sel && !sel.isCollapsed && sel.toString().trim() !== "") return
      const raw = (cell.textContent || "").trim()
      if (raw === "") return
      // Peek JSON values always (to pretty-print them); peek other values only
      // when the cell is actually clipped — a fully visible short value needs no
      // popover.
      const isJson = raw[0] === "{" || raw[0] === "["
      if (!isJson && cell.scrollWidth <= cell.clientWidth + 1) return
      this._showCellPeek(cell, raw)
    })

    // Dismiss the peek on outside-click, Esc, or any scroll (it's position:fixed,
    // so it would otherwise float away from its cell).
    this._cellPeekOutside = (e) => {
      if (this._cellPeekEl && !this._cellPeekEl.contains(e.target) && !e.target.closest(".lt-td")) {
        this._hideCellPeek()
      }
    }
    this._cellPeekKey = (e) => {
      if (e.key === "Escape") this._hideCellPeek()
    }
    this._cellPeekScroll = () => this._hideCellPeek()
    document.addEventListener("mousedown", this._cellPeekOutside, true)
    document.addEventListener("keydown", this._cellPeekKey)
    window.addEventListener("scroll", this._cellPeekScroll, true)
    window.addEventListener("resize", this._cellPeekScroll)

    // Cell actions menu: right-click a data cell to open a menu at the cursor
    // with Copy value, Filter by this value, and (for FK cells) Open FK. All
    // three are reads, so this works even when the explorer is read-only.
    this._cellMenuEl = null
    this.el.addEventListener("contextmenu", (e) => {
      const cell = e.target.closest(".lt-td")
      // Only data cells carry data-col; checkbox/actions cells don't, so we skip
      // them (and the SQL-results grid, whose cells have no data-col either).
      if (!cell || !this.el.contains(cell) || !cell.dataset.col) return
      e.preventDefault()
      this._hideCellPeek()
      this._showCellMenu(cell, e.clientX, e.clientY)
    })

    this._cellMenuOutside = (e) => {
      if (this._cellMenuEl && !this._cellMenuEl.contains(e.target)) this._hideCellMenu()
    }
    this._cellMenuKey = (e) => {
      if (e.key === "Escape") this._hideCellMenu()
    }
    this._cellMenuScroll = () => this._hideCellMenu()
    document.addEventListener("mousedown", this._cellMenuOutside, true)
    document.addEventListener("keydown", this._cellMenuKey)
    window.addEventListener("scroll", this._cellMenuScroll, true)
    window.addEventListener("resize", this._cellMenuScroll)
  },

  _showCellPeek(cell, raw) {
    // One reusable popover element, themed by being a child of .lantern. Recreate
    // it if a LiveView re-render (morphdom) detached our JS-added node.
    if (!this._cellPeekEl || !this._cellPeekEl.isConnected) {
      this._cellPeekEl = document.createElement("div")
      this._cellPeekEl.className = "lt-cellpeek"
      this.el.appendChild(this._cellPeekEl)
    }
    this._cellPeekEl.textContent = this._prettyValue(raw)
    this._cellPeekEl.style.visibility = "hidden"
    this._cellPeekEl.style.display = "block"

    // Position near the cell, clamped to the viewport.
    const r = cell.getBoundingClientRect()
    const pop = this._cellPeekEl
    const pw = pop.offsetWidth
    const ph = pop.offsetHeight
    const margin = 6
    let left = r.left
    let top = r.bottom + 4
    if (left + pw > window.innerWidth - margin) left = window.innerWidth - pw - margin
    if (left < margin) left = margin
    if (top + ph > window.innerHeight - margin) {
      const above = r.top - ph - 4
      top = above >= margin ? above : Math.max(margin, window.innerHeight - ph - margin)
    }
    pop.style.left = left + "px"
    pop.style.top = top + "px"
    pop.style.visibility = "visible"
  },

  _hideCellPeek() {
    if (this._cellPeekEl) this._cellPeekEl.style.display = "none"
  },

  // Pretty-print JSON-looking values (objects/arrays) with 2-space indent;
  // leave everything else as-is.
  _prettyValue(raw) {
    const first = raw[0]
    if (first === "{" || first === "[") {
      try {
        return JSON.stringify(JSON.parse(raw), null, 2)
      } catch {}
    }
    return raw
  },

  _showCellMenu(cell, x, y) {
    const col = cell.dataset.col
    const value = (cell.textContent || "").trim()
    const isFk = cell.dataset.fk === "1"
    // The FK link sends a coerced value (e.g. quotes stripped) to open_fk; reuse
    // it so "Open FK" behaves exactly like clicking the link.
    const fkValue = cell.dataset.fkValue != null ? cell.dataset.fkValue : value

    // One reusable menu element, themed by being a child of .lantern. Recreate
    // it if a LiveView re-render (morphdom) detached our JS-added node.
    if (!this._cellMenuEl || !this._cellMenuEl.isConnected) {
      this._cellMenuEl = document.createElement("div")
      this._cellMenuEl.className = "lt-cellmenu"
      this.el.appendChild(this._cellMenuEl)
    }
    const menu = this._cellMenuEl
    menu.replaceChildren()

    const addItem = (label, onClick) => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "lt-cellmenu-item"
      btn.textContent = label
      btn.addEventListener("click", () => {
        onClick()
        this._hideCellMenu()
      })
      menu.appendChild(btn)
    }

    addItem("Copy value", () => {
      if (navigator.clipboard) navigator.clipboard.writeText(value)
    })
    addItem("Filter by this value", () => {
      this.pushEventTo(this.el, "filter_by_cell", { column: col, value })
    })
    if (isFk) {
      addItem("Open FK", () => {
        this.pushEventTo(this.el, "open_fk", { column: col, value: fkValue })
      })
    }

    // Position at the cursor, clamped to the viewport (flip left/up on overflow).
    menu.style.visibility = "hidden"
    menu.style.display = "flex"
    const mw = menu.offsetWidth
    const mh = menu.offsetHeight
    const margin = 6
    let left = x
    let top = y
    if (left + mw > window.innerWidth - margin) left = Math.max(margin, x - mw)
    if (top + mh > window.innerHeight - margin) top = Math.max(margin, y - mh)
    menu.style.left = left + "px"
    menu.style.top = top + "px"
    menu.style.visibility = "visible"
  },

  _hideCellMenu() {
    if (this._cellMenuEl) this._cellMenuEl.style.display = "none"
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

    // A re-render may have replaced the cell the peek/menu was anchored to.
    this._hideCellPeek()
    this._hideCellMenu()
  },

  destroyed() {
    if (this._dragMove) window.removeEventListener("pointermove", this._dragMove)
    if (this._dragUp) {
      window.removeEventListener("pointerup", this._dragUp)
      window.removeEventListener("pointercancel", this._dragUp)
    }
    this._dragMove = null
    this._dragUp = null

    document.removeEventListener("mousedown", this._cellPeekOutside, true)
    document.removeEventListener("keydown", this._cellPeekKey)
    window.removeEventListener("scroll", this._cellPeekScroll, true)
    window.removeEventListener("resize", this._cellPeekScroll)
    if (this._cellPeekEl) {
      this._cellPeekEl.remove()
      this._cellPeekEl = null
    }

    document.removeEventListener("mousedown", this._cellMenuOutside, true)
    document.removeEventListener("keydown", this._cellMenuKey)
    window.removeEventListener("scroll", this._cellMenuScroll, true)
    window.removeEventListener("resize", this._cellMenuScroll)
    if (this._cellMenuEl) {
      this._cellMenuEl.remove()
      this._cellMenuEl = null
    }
  },
}

export default { LanternGrid }
