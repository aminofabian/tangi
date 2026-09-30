defmodule ViewNinjas.Orders.SupplierStatus do
  @moduledoc """
  Maps a panel's own words onto our order states (scope.md §10).

  An unrecognized word is not guessed at: the caller keeps the previous state and
  stores the raw string, so an admin can see exactly what the panel said.
  """

  @mapping %{
    "awaiting" => :placed,
    "pending" => :placed,
    "in progress" => :in_progress,
    "inprogress" => :in_progress,
    "processing" => :in_progress,
    "completed" => :completed,
    "complete" => :completed,
    "partial" => :partial,
    "canceled" => :canceled,
    "cancelled" => :canceled,
    "refunded" => :canceled
  }

  @doc "Our state for a panel's word, or nil when we do not know it."
  @spec map(String.t() | nil) :: atom() | nil
  def map(raw) when is_binary(raw) do
    raw
    |> String.trim()
    |> String.downcase()
    |> then(&Map.get(@mapping, &1))
  end

  def map(_raw), do: nil

  @doc "The words we understand, for admin copy and tests."
  @spec known() :: [String.t()]
  def known, do: @mapping |> Map.keys() |> Enum.sort()
end
