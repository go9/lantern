import { Socket } from "https://cdn.jsdelivr.net/npm/phoenix@1.8.7/+esm"
import { LiveSocket } from "https://cdn.jsdelivr.net/npm/phoenix_live_view@1.1.30/+esm"
import { LanternGrid } from "/lantern/hooks.js"
import { LiveCode } from "/livecode/livecode.js"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: { LanternGrid, LiveCode },
  params: { _csrf_token: csrfToken },
})

liveSocket.connect()
window.liveSocket = liveSocket
