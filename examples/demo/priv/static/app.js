import { Socket } from "https://cdn.jsdelivr.net/npm/phoenix@1.8.7/+esm"
import { LiveSocket } from "/js/phoenix_live_view.esm.js"
import { LanternGrid } from "/lantern/hooks.js"
import { LiveCode } from "/livecode/livecode.js"

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

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: { LanternGrid, LiveCode, TurnstileWidget },
  params: { _csrf_token: csrfToken },
})

liveSocket.connect()
window.liveSocket = liveSocket
