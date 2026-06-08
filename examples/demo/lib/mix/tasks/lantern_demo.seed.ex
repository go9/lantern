defmodule Mix.Tasks.LanternDemo.Seed do
  @moduledoc "Creates and seeds the local Lantern demo database."

  use Mix.Task

  @shortdoc "Creates and seeds demo tables"

  @impl true
  def run(_args) do
    Mix.Task.run("app.config")
    Application.ensure_all_started(:postgrex)
    Application.ensure_all_started(:decimal)
    Application.ensure_all_started(:jason)

    Mix.shell().info("Seeding #{LanternDemo.DemoDB.url()} ...")
    LanternDemo.DemoDB.ensure!()
    Mix.shell().info("Lantern demo database is ready.")
  end
end
