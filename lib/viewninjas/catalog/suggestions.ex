defmodule ViewNinjas.Catalog.Suggestions do
  @moduledoc """
  Candidates for a lane, ranked but **never auto-published** (scope.md §9).

  Given the service an admin is reading, it offers the cheapest refillable
  service, the cheapest of any kind, and the closest name match — all from the
  ingested inventory, in the same category when there is one. Suggestions fill
  the shortlist; publishing stays a human decision, not a price or a name.
  """
  import Ecto.Query

  alias ViewNinjas.Repo
  alias ViewNinjas.Suppliers.SupplierService

  @candidates 200

  @type suggestion :: %{reason: atom(), service: SupplierService.t()}

  @doc "Ranked candidates for the given service."
  @spec for_service(SupplierService.t(), keyword()) :: [suggestion()]
  def for_service(%SupplierService{} = service, opts \\ []) do
    candidates = candidates(service, Keyword.get(opts, :candidates, @candidates))

    [
      {:cheapest_refillable, cheapest(Enum.filter(candidates, & &1.refill))},
      {:cheapest, cheapest(candidates)},
      {:name_match, best_name_match(candidates, service.name)}
    ]
    |> Enum.reject(fn {_reason, candidate} -> is_nil(candidate) end)
    |> Enum.uniq_by(fn {_reason, candidate} -> candidate.id end)
  end

  @doc "The label shown beside a suggestion."
  @spec label(atom()) :: String.t()
  def label(:cheapest_refillable), do: "Cheapest refillable"
  def label(:cheapest), do: "Cheapest of any kind"
  def label(:name_match), do: "Closest name"
  def label(other), do: to_string(other)

  defp candidates(%SupplierService{} = service, limit) do
    SupplierService
    |> where([s], s.active and s.id != ^service.id)
    |> filter_category(service.category)
    |> order_by([s], asc: s.rate_micros)
    |> limit(^limit)
    |> preload(:supplier)
    |> Repo.all()
  end

  defp filter_category(query, nil), do: query
  defp filter_category(query, category), do: where(query, [s], s.category == ^category)

  defp cheapest([]), do: nil
  defp cheapest([service | _]), do: service

  # Ranks by token overlap; the list is already cheapest-first, so ties go to the
  # cheaper service.
  defp best_name_match(candidates, name) when is_binary(name) do
    wanted = tokens(name)

    best =
      candidates
      |> Enum.map(fn candidate -> {overlap(wanted, tokens(candidate.name)), candidate} end)
      |> Enum.filter(fn {score, _candidate} -> score > 0 end)
      |> Enum.max_by(fn {score, _candidate} -> score end, fn -> nil end)

    case best do
      nil -> nil
      {_score, candidate} -> candidate
    end
  end

  defp best_name_match(_candidates, _name), do: nil

  defp tokens(nil), do: MapSet.new()

  defp tokens(name) do
    name
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
    |> Enum.reject(&(String.length(&1) < 3))
    |> MapSet.new()
  end

  defp overlap(a, b), do: a |> MapSet.intersection(b) |> MapSet.size()
end
