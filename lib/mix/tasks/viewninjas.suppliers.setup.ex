defmodule Mix.Tasks.Viewninjas.Suppliers.Setup do
  @shortdoc "Creates or updates the wholesale panel rows from the environment"

  @moduledoc """
  One row per panel: slug, base URL, encrypted API key and capabilities
  (scope.md §5). Keys come from the environment and are encrypted on write —
  they never touch a config file or the repo.

      SECSERS_API_KEY=... JAP_API_KEY=... SMMFOLLOWS_API_KEY=... \\
        mix viewninjas.suppliers.setup

  Base URLs default to the collected ones and can be overridden with
  `<SLUG>_BASE_URL`. Pass `--activate` to flip a panel on; without it an
  existing row keeps whatever `active` it already had.

  Idempotent: run it again to rotate a key.
  """

  use Mix.Task

  alias ViewNinjas.Suppliers

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _argv, invalid} = OptionParser.parse(argv, strict: [activate: :boolean])

    if invalid != [] do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    activate? = Keyword.get(opts, :activate, false)

    panels = Application.get_env(:viewninjas, :suppliers, [])[:panels] || []

    if panels == [] do
      Mix.raise("No panels configured under :viewninjas, :suppliers, :panels")
    end

    Enum.each(panels, &setup_panel(&1, activate?))
  end

  defp setup_panel(panel, activate?) do
    env = String.upcase(panel.slug)
    api_key = System.get_env("#{env}_API_KEY")

    if is_nil(api_key) do
      Mix.shell().info("#{panel.slug}: skipped (no #{env}_API_KEY)")
    else
      save_panel(panel, api_key, activate?)
    end
  end

  defp save_panel(panel, api_key, activate?) do
    base_url = System.get_env("#{String.upcase(panel.slug)}_BASE_URL") || panel.base_url

    attrs = %{
      slug: panel.slug,
      base_url: base_url,
      api_key: api_key,
      capabilities: panel.capabilities
    }

    attrs = if activate?, do: Map.put(attrs, :active, true), else: attrs

    case Suppliers.upsert_supplier(attrs) do
      {:ok, supplier} ->
        state = if supplier.active, do: "active", else: "inactive"
        Mix.shell().info("#{supplier.slug}: #{state} (#{supplier.base_url})")

      {:error, changeset} ->
        Mix.raise("#{panel.slug} could not be saved: #{inspect(changeset.errors)}")
    end
  end
end
