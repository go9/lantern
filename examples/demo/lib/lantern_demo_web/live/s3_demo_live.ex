defmodule LanternDemoWeb.S3DemoLive do
  @moduledoc """
  Public S3 upload sandbox (flicker #986).

  Anonymous visitors exercise the real lantern-s3 upload flow (drag-drop,
  progress, cancel/clear) against real object storage, bounded to be safe:
  Turnstile-gated, slot-limited with a FIFO wait queue (shared `SandboxManager`),
  1-minute TTL, and per-session prefix isolation. `S3Sandbox.Adapter` enforces
  type + safe keys server-side; `allow_upload` enforces count/size/aggregate;
  the completion sweep deletes anything a lying client slipped past.

  Reuses the DB demo's sandbox state machine and Turnstile flow verbatim, only
  swapping the `:db` pool for `:s3` and the active surface for the Uploader.
  """
  use Phoenix.LiveView

  alias LanternDemo.S3Sandbox.Limits
  alias LanternDemo.S3Sandbox.Storage
  alias LanternS3.Scope
  alias LanternS3.Storage.S3

  @accept ~w(.jpg .jpeg .png .webp .gif .pdf)

  @impl true
  def mount(_params, _session, socket) do
    # Called at upload completion by the embedded Uploader; runs in this process.
    on_event = fn event, meta -> send(self(), {:s3_upload_event, event, meta}) end

    {:ok,
     assign(socket,
       theme: "system",
       configured?: Storage.configured?(),
       sandbox: :none,
       accept: @accept,
       on_event: on_event,
       turnstile_site_key: LanternDemo.Captcha.site_key()
     )}
  end

  @impl true
  def terminate(_reason, socket) do
    release_current(socket.assigns.sandbox)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("request_sandbox", _params, socket) do
    if socket.assigns.configured? do
      {:noreply, assign(socket, sandbox: :verifying)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("sandbox_token", %{"token" => token}, socket) do
    case LanternDemo.Captcha.verify(token) do
      :ok ->
        lv = self()

        Task.start(fn ->
          result =
            try do
              LanternDemo.SandboxManager.claim(:s3, lv)
            catch
              :exit, _ -> {:error, "Sandbox creation timed out — please try again."}
            end

          send(lv, {:claim_result, result})
        end)

        {:noreply, assign(socket, sandbox: :creating)}

      {:error, reason} ->
        {:noreply, assign(socket, sandbox: {:error, reason})}
    end
  end

  def handle_event("release_sandbox", _params, socket) do
    release_current(socket.assigns.sandbox)
    {:noreply, assign(socket, sandbox: :none)}
  end

  # ---------------------------------------------------------------------------
  # Sandbox lifecycle messages (mirror DemoLive)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:claim_result, {:granted, grant}}, socket) do
    {:noreply, activate(socket, grant)}
  end

  def handle_info({:claim_result, {:queued, %{ref: ref, position: position}}}, socket) do
    {:noreply, assign(socket, sandbox: {:queued, ref, position})}
  end

  def handle_info({:claim_result, {:error, reason}}, socket) do
    {:noreply, assign(socket, sandbox: {:error, humanize(reason)})}
  end

  def handle_info({:sandbox_granted, ref, grant}, socket) do
    case socket.assigns.sandbox do
      {:queued, ^ref, _} -> {:noreply, activate(socket, Map.put(grant, :ref, ref))}
      _ -> {:noreply, socket}
    end
  end

  def handle_info({:queue_position, ref, position}, socket) do
    case socket.assigns.sandbox do
      {:queued, ^ref, _} -> {:noreply, assign(socket, sandbox: {:queued, ref, position})}
      _ -> {:noreply, socket}
    end
  end

  def handle_info({:sandbox_failed, ref, reason}, socket) do
    case socket.assigns.sandbox do
      {:queued, ^ref, _} -> {:noreply, assign(socket, sandbox: {:error, humanize(reason)})}
      _ -> {:noreply, socket}
    end
  end

  def handle_info({:sandbox_expired, ref}, socket) do
    case socket.assigns.sandbox do
      {:active, %{ref: ^ref}} -> {:noreply, assign(socket, sandbox: :expired)}
      _ -> {:noreply, socket}
    end
  end

  def handle_info(:sandbox_tick, socket) do
    case socket.assigns.sandbox do
      {:active, %{ticks: ticks} = session} when ticks > 1 ->
        schedule_tick()
        {:noreply, assign(socket, sandbox: {:active, %{session | ticks: ticks - 1}})}

      {:active, %{ref: ref}} ->
        LanternDemo.SandboxManager.release(ref)
        {:noreply, assign(socket, sandbox: :expired)}

      _ ->
        {:noreply, socket}
    end
  end

  # Upload completion: the Explorer forwards the uploader's completion as an
  # `:upload` event. Sweep each key, dropping anything oversize / wrong-type that
  # slipped past the client, then re-list so deletions are reflected.
  def handle_info({:s3_upload_event, :upload, %{keys: keys}}, socket) do
    case socket.assigns.sandbox do
      {:active, session} ->
        # Delete anything oversize/wrong-type that slipped past the client. The
        # sweep's HEADs also confirm each object exists, so refresh the listing
        # afterwards: the Explorer's own re-list on :uploaded fires the instant the
        # PUT completes and can race ahead of LIST consistency, leaving the browser
        # empty. `refresh:` re-lists WITHOUT re-emitting :upload (which would loop
        # straight back into this handler).
        survivors = sweep_completed(session, keys)
        merged = merge_files(session.files, survivors)
        send_update(LanternS3.Explorer, id: "s3-sandbox-explorer", refresh: true)
        {:noreply, assign(socket, sandbox: {:active, %{session | files: merged}})}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:s3_upload_event, _event, _meta}, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp activate(socket, %{ref: ref, ttl: ttl, payload: %{bucket: bucket, prefix: prefix}}) do
    schedule_tick()

    assign(socket,
      sandbox: {:active, %{ref: ref, bucket: bucket, prefix: prefix, ticks: ttl, files: []}}
    )
  end

  defp release_current({:active, %{ref: ref}}), do: LanternDemo.SandboxManager.release(ref)
  defp release_current({:queued, ref, _}), do: LanternDemo.SandboxManager.release(ref)
  defp release_current(_), do: :ok

  defp schedule_tick, do: Process.send_after(self(), :sandbox_tick, 1_000)

  defp humanize(:queue_full),
    do: "The wait queue is full right now — please try again in a few minutes."

  defp humanize(reason) when is_binary(reason), do: reason
  defp humanize(_), do: "Something went wrong — please try again."

  # Post-upload defense in depth: HEAD each key, delete any object over the size
  # cap or with a non-allowlisted content-type, and presign a short GET for the
  # survivors. HEAD returns the raw ExAws response, so headers are parsed
  # case-insensitively.
  # The whole S3 interface: one lantern-s3 Explorer (browse + upload + download +
  # delete), locked to this session's own prefix (root_prefix) so it can only ever
  # see/act on the visitor's uploads, never another session's. Its built-in
  # uploader is wired to the GATED sandbox adapter + the type/size/count limits,
  # so uploads are policy-enforced despite being a public surface.
  defp explorer_scope(%{bucket: bucket, prefix: prefix}, on_event) do
    {:ok, config} = Storage.s3_config()

    Scope.new(
      adapter: S3,
      config: config,
      buckets: [%{name: bucket, label: "Your files"}],
      capabilities: [:upload, :download, :delete],
      auto_open: true,
      root_prefix: prefix,
      on_event: on_event,
      upload_adapter: LanternDemo.S3Sandbox.Adapter,
      upload_opts: %{accept: @accept, max_entries: 5, max_file_size: 5_242_880}
    )
  end

  defp sweep_completed(session, entries) do
    case Storage.s3_config() do
      {:ok, config} ->
        Enum.flat_map(entries, &sweep_key(config, session.bucket, entry_key(&1)))

      {:error, _} ->
        []
    end
  end

  # The uploader reports each completed file as a descriptor map (%{key, name,
  # size, url}); tolerate a bare string key too.
  defp entry_key(%{key: key}), do: key
  defp entry_key(key) when is_binary(key), do: key

  defp sweep_key(config, bucket, key) do
    with {:ok, meta} <- S3.head(config, bucket, key),
         size = header_int(meta, "content-length"),
         content_type = header(meta, "content-type"),
         ext = key |> Path.extname() |> String.trim_leading("."),
         true <- allowed_object?(size, ext, content_type) do
      case S3.presigned_get(config, bucket, key, expires_in: 300) do
        {:ok, url} -> [%{key: key, name: Path.basename(key), size: size, url: url}]
        _ -> []
      end
    else
      false ->
        # Oversize or wrong type despite the client — delete it and surface nothing.
        S3.delete_many(config, bucket, [key])
        []

      _ ->
        []
    end
  end

  defp allowed_object?(size, ext, content_type) do
    is_integer(size) and size <= Limits.max_file_bytes() and
      Limits.validate_type(ext, content_type || "") == :ok
  end

  defp header(%{headers: headers}, name) when is_list(headers) do
    Enum.find_value(headers, fn {k, v} ->
      if String.downcase(to_string(k)) == name, do: v
    end)
  end

  defp header(_meta, _name), do: nil

  defp header_int(meta, name) do
    case header(meta, name) do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, _} -> int
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp merge_files(existing, new) do
    keys = MapSet.new(existing, & &1.key)
    existing ++ Enum.reject(new, &MapSet.member?(keys, &1.key))
  end

  defp format_time(seconds) do
    m = div(seconds, 60)
    s = rem(seconds, 60)
    "#{m}:#{String.pad_leading(to_string(s), 2, "0")}"
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <LanternDemoWeb.DocsShell.shell current="s3" theme={@theme}>
      <div class="demo-shell" data-demo-theme={@theme}>
        <section class="demo-hero">
          <p class="demo-eyebrow">Lantern S3</p>
          <h1 class="demo-title">A drag-and-drop file manager for any S3 bucket.</h1>
          <p class="demo-copy">
            <code>lantern-s3</code>
            drops a storage-agnostic uploader and browser into any LiveView —
            direct-to-S3 uploads with progress, cancel, and clear. This live demo gives you a
            private, ephemeral workspace: uploads are capped, links expire, and everything is
            deleted when your 1-minute session ends.
            <a href="https://github.com/go9/lantern-s3" target="_blank" rel="noopener">
              View on GitHub →
            </a>
          </p>
        </section>

        <%!-- Not configured --%>
        <section :if={!@configured?} class="demo-panel demo-warning">
          The upload demo is being set up. In the meantime, the source is on
          <a href="https://github.com/go9/lantern-s3" target="_blank" rel="noopener">GitHub</a>.
        </section>

        <%!-- Idle / expired / error: the try-it bar --%>
        <section
          :if={@configured? and (@sandbox in [:none, :expired] or match?({:error, _}, @sandbox))}
          class="demo-panel demo-sandbox-bar"
        >
          <div class="demo-sandbox-desc">
            {if @sandbox == :expired do
              "Session expired — your uploads were deleted."
            else
              "Try the real uploader against live storage. jpg/png/webp/gif/pdf, up to 5 files, 5 MB each — a private 1-minute session."
            end}
            <span :if={match?({:error, _}, @sandbox)} class="demo-error-text">
              {elem(@sandbox, 1)}
            </span>
          </div>
          <div class="demo-sandbox-actions">
            <button phx-click="request_sandbox" class="demo-btn demo-btn-primary">
              {if @sandbox == :expired, do: "New session", else: "Try uploads →"}
            </button>
          </div>
        </section>

        <%!-- Turnstile --%>
        <section :if={@sandbox in [:verifying, :creating]} class="demo-panel demo-captcha-panel">
          <p :if={@sandbox == :verifying} class="demo-captcha-hint">
            Complete the challenge to unlock your private 1-minute upload session.
          </p>
          <p :if={@sandbox == :creating} class="demo-captcha-hint">Reserving your session…</p>
          <div
            :if={@sandbox == :verifying}
            id="turnstile-widget"
            phx-hook="TurnstileWidget"
            data-sitekey={@turnstile_site_key}
            phx-update="ignore"
          >
          </div>
        </section>

        <%!-- Queue --%>
        <section :if={match?({:queued, _, _}, @sandbox)} class="demo-panel demo-warning demo-sandbox-bar">
          <div class="demo-sandbox-desc">
            <span class="demo-readonly-badge">Queued</span>
            Demo is full — you're <strong>{elem(@sandbox, 2)}</strong> in line.
            Your session starts automatically when a slot opens; keep this tab open.
          </div>
          <div class="demo-sandbox-actions">
            <button phx-click="release_sandbox" class="demo-btn demo-btn-sm">Leave queue</button>
          </div>
        </section>

        <%!-- Active session --%>
        <section :if={match?({:active, _}, @sandbox)} class="demo-panel demo-sandbox-active">
          <div class="demo-sandbox-active-top">
            <span class="demo-sandbox-live-dot"></span>
            <span class="demo-sandbox-live-label">Live upload session</span>
            <span class="demo-sandbox-timer">
              {format_time(elem(@sandbox, 1).ticks)} remaining
            </span>
            <button phx-click="release_sandbox" class="demo-btn demo-btn-sm">End session</button>
          </div>

          <.live_component
            module={LanternS3.Explorer}
            id="s3-sandbox-explorer"
            scope={explorer_scope(elem(@sandbox, 1), @on_event)}
          />

          <p class="demo-uploaded-note">
            The real lantern-s3 file manager (browse · upload · download · delete),
            scoped to your private session prefix — everything here is deleted when
            your session ends.
          </p>
        </section>
      </div>
    </LanternDemoWeb.DocsShell.shell>
    """
  end
end
