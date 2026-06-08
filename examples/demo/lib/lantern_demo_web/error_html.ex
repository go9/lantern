defmodule LanternDemoWeb.ErrorHTML do
  use Phoenix.Component

  def render(_template, assigns) do
    ~H"""
    <main class="demo-shell">
      <section class="demo-panel demo-error">
        <h1>Something went wrong.</h1>
        <p>Restart the demo server and check the terminal output.</p>
      </section>
    </main>
    """
  end
end
