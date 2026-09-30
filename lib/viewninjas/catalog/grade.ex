defmodule ViewNinjas.Catalog.Grade do
  @moduledoc """
  The three lanes a buyer chooses between (scope.md §6, §7).

  A grade changes which wholesale service backs it, not the markup applied, so
  the price gap between Cheap and Quality is the real cost gap with nothing
  stacked on top. One lane per grade per offer.
  """

  @type t :: :cheap | :moderate | :quality

  @grades [:cheap, :moderate, :quality]

  @doc "All grades, in the order they are shown."
  @spec all() :: [t()]
  def all, do: @grades

  @doc "The display rank of a grade — cheapest first."
  @spec rank(t() | term()) :: non_neg_integer()
  def rank(grade), do: Enum.find_index(@grades, &(&1 == grade)) || length(@grades)

  @doc "The buyer-facing label."
  @spec label(term()) :: String.t()
  def label(:cheap), do: "Cheap"
  def label(:moderate), do: "Moderate"
  def label(:quality), do: "Quality"
  def label(other), do: to_string(other)

  @doc """
  Parses a grade from an atom or a string.

      iex> ViewNinjas.Catalog.Grade.parse("cheap")
      {:ok, :cheap}

      iex> ViewNinjas.Catalog.Grade.parse("premium")
      :error
  """
  @spec parse(term()) :: {:ok, t()} | :error
  def parse(grade) when grade in @grades, do: {:ok, grade}

  def parse(grade) when is_binary(grade) do
    case Enum.find(@grades, &(Atom.to_string(&1) == grade)) do
      nil -> :error
      grade -> {:ok, grade}
    end
  end

  def parse(_), do: :error
end
