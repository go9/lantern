defmodule LanternDemoWeb.ComponentBatchPreviewLive do
  @moduledoc false
  use Phoenix.LiveView
  use LanternUI

  @games [
    {"The Legend of Zelda: Ocarina of Time", "zelda-ocarina"},
    {"The Legend of Zelda: Majora's Mask", "zelda-majora"},
    {"Super Mario 64", "mario-64"},
    {"Metroid Prime", "metroid-prime"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, games: [], deleted?: false)}
  end

  @impl true
  def handle_event("search_games", %{"query" => query}, socket) do
    Process.sleep(120)
    query = String.downcase(query)
    games = Enum.filter(@games, fn {label, _value} -> String.contains?(String.downcase(label), query) end)
    {:noreply, assign(socket, games: games)}
  end

  def handle_event("confirm_delete", _params, socket) do
    {:noreply,
     socket
     |> assign(:deleted?, true)
     |> LanternUI.close_dialog("batch-delete")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main style="max-width: 72rem; margin: 0 auto; padding: 2rem; display: grid; gap: 2rem;">
      <header>
        <p style="margin: 0; color: var(--lantern-fg-muted);">Temporary integration harness</p>
        <h1 style="margin: .25rem 0 0; font-family: var(--lantern-font-brand);">Lantern UI component batch</h1>
      </header>

      <section aria-labelledby="stats-title">
        <h2 id="stats-title">Stat cards</h2>
        <.stat_grid aria-label="Store summary">
          <:stat label="Open orders" value={42} icon="hero-inbox" />
          <:stat label="Shipped" href="/components" subtitle="View components">128</:stat>
          <:stat label="Long value" value="SUPERCALIFRAGILISTICEXPIALIDOCIOUS-1234567890" />
          <:stat label="Revenue" value="$12,482.19" />
        </.stat_grid>
      </section>

      <section aria-labelledby="skeleton-title" aria-busy="true">
        <h2 id="skeleton-title">Skeletons</h2>
        <div style="display: grid; grid-template-columns: 3rem 1fr; gap: .75rem; align-items: center; max-width: 34rem;">
          <.skeleton style="width: 3rem; height: 3rem; border-radius: 9999px;" />
          <div style="display: grid; gap: .5rem;">
            <.skeleton style="width: 70%;" />
            <.skeleton style="width: 42%; height: .75rem;" />
          </div>
        </div>
      </section>

      <section aria-labelledby="accordion-title">
        <h2 id="accordion-title">Accordion</h2>
        <.accordion id="batch-accordion" prevent_all_closed>
          <.accordion_item id="template-help" expanded>
            <:header>Where would we use this?</:header>
            <:panel>Template syntax help, deploy key details, raw JSON, reasoning, history diffs, and pipeline payloads.</:panel>
          </.accordion_item>
          <.accordion_item id="fluxon-parity">
            <:header>Does it mirror Fluxon?</:header>
            <:panel>Yes. The public container and item APIs mirror Fluxon 2.3.1.</:panel>
          </.accordion_item>
        </.accordion>
      </section>

      <section aria-labelledby="autocomplete-title">
        <h2 id="autocomplete-title">Async autocomplete</h2>
        <.autocomplete
          id="game-search"
          name="game"
          label="Search remote catalog"
          placeholder="Type at least 2 characters"
          search_threshold={2}
          debounce={180}
          on_search="search_games"
          options={@games}
          clearable
          open_on_focus
        >
          <:option :let={{label, value}}>
            <span style="display: flex; justify-content: space-between; width: 100%; gap: 1rem;">
              <strong>{label}</strong><small>{value}</small>
            </span>
          </:option>
          <:empty_state><p style="padding: 1rem; margin: 0;">No matching games.</p></:empty_state>
        </.autocomplete>
      </section>

      <section aria-labelledby="dialog-title">
        <h2 id="dialog-title">Alert dialog</h2>
        <.button id="open-delete" color="danger" phx-click={LanternUI.open_dialog("batch-delete")}>Delete test record</.button>
        <p :if={@deleted?} id="delete-result" role="status">Delete action received.</p>
        <.alert_dialog id="batch-delete">
          <:title>Delete this test record?</:title>
          <:description>This demonstrates safe initial focus and destructive confirmation semantics.</:description>
          <:cancel><.button id="cancel-delete" phx-click={LanternUI.close_dialog("batch-delete")}>Cancel</.button></:cancel>
          <:action><.button id="confirm-delete" color="danger" phx-click="confirm_delete">Delete</.button></:action>
        </.alert_dialog>
      </section>
    </main>
    """
  end
end
