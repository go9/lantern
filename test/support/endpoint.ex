defmodule Lantern.TestEndpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :lantern

  socket("/live", Phoenix.LiveView.Socket,
    websocket: false,
    longpoll: false
  )
end
