defmodule LanternDemoWeb.LiveCodeDemoLive do
  @moduledoc """
  livecode — a LiveView-native code editor (syntax highlighting, autocomplete,
  snippets, diagnostics) that upgrades a plain `<textarea>`, no JS framework.

  This page embeds it with a seeded HEEx snippet you can edit live; it's entirely
  client-side (the editor's own hook manages the textarea) so there is no server
  write surface here — unlike the S3 demo, this needs no sandbox or gating.
  """
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <LanternDemoWeb.DocsShell.shell current="livecode" theme="system">
      <div class="demo-shell">
        <section class="demo-hero">
          <p class="demo-eyebrow">LiveCode</p>
          <h1 class="demo-title">A real code editor, in a textarea.</h1>
          <p class="demo-copy">
            <code>livecode</code>
            adds syntax highlighting, autocomplete, snippets, and diagnostics to a plain
            <code>&lt;textarea&gt;</code>
            — LiveView-native, no JS framework to adopt. Edit the HEEx below and watch it
            highlight as you type.
            <a href="https://github.com/go9/livecode" target="_blank" rel="noopener">
              View on GitHub →
            </a>
          </p>
        </section>

        <section class="demo-panel">
          <LiveCode.Editor.editor
            id="livecode-demo"
            language={LiveCode.Languages.HEEx}
            value={String.trim(snippet())}
            class="docs-codeblock"
          />
        </section>
      </div>
    </LanternDemoWeb.DocsShell.shell>
    """
  end

  defp snippet do
    """
    <.form for={@form} phx-submit="save">
      <.input field={@form[:name]} label="Name" />
      <.input field={@form[:email]} type="email" label="Email" />

      <:actions>
        <.button phx-disable-with="Saving…">Save profile</.button>
      </:actions>
    </.form>
    """
  end
end
