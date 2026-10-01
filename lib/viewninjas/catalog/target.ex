defmodule ViewNinjas.Catalog.Target do
  @moduledoc """
  What the buyer pastes a link to (scope.md §2, step 5).

  An offer is a platform **and** an outcome, and that is not always enough to
  describe the product. Facebook sells page likes and post likes as two different
  services at two different prices, and Instagram sells followers, post likes and
  reel likes. They collapsed into one "Facebook likes" row because the offer had
  nowhere to record *which* thing is being liked.

  A target is that missing dimension: the noun the link points at. It is **empty**
  by default, because most offers do not need it — "Instagram followers" needs no
  target to be unambiguous. It is set only where it separates two genuinely
  different products.
  """

  @type t :: :page | :post | :video | :reel | :profile | :channel | :comment

  @targets [:page, :post, :video, :reel, :profile, :channel, :comment]

  @doc "Every known target, in a sensible reading order."
  @spec all() :: [t()]
  def all, do: @targets

  @doc "The buyer-facing label, singular and lowercase so it reads inside a title."
  @spec label(t() | term()) :: String.t()
  def label(:page), do: "page"
  def label(:post), do: "post"
  def label(:video), do: "video"
  def label(:reel), do: "reel"
  def label(:profile), do: "profile"
  def label(:channel), do: "channel"
  def label(:comment), do: "comment"
  def label(other), do: to_string(other)

  @doc """
  The label for a stored target, where an empty string means "not set".

  Returns `""` rather than a placeholder so a caller can drop it straight into a
  title without having to test for it first.
  """
  @spec label_or_blank(String.t() | nil) :: String.t()
  def label_or_blank(nil), do: ""
  def label_or_blank(""), do: ""
  def label_or_blank(target), do: label(parse!(target))

  @doc """
  How the offer reads on the shop: the target and the outcome together.

  A target changes what the offer *is*, so it belongs in the name the buyer reads
  rather than in a filter they have to remember — "Page likes" and "Post likes"
  are two things to buy, not one thing with two settings.

      iex> ViewNinjas.Catalog.Target.summary("page", "likes")
      "Page likes"

      iex> ViewNinjas.Catalog.Target.summary("", "followers")
      "Followers"
  """
  @spec summary(String.t() | nil, String.t() | nil) :: String.t()
  def summary(target, outcome) do
    [target |> label_or_blank() |> String.capitalize(), String.capitalize(outcome || "")]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  @doc """
  Parses a stored target string into an atom.

      iex> ViewNinjas.Catalog.Target.parse("page")
      {:ok, :page}

      iex> ViewNinjas.Catalog.Target.parse("something else")
      :error
  """
  @spec parse(String.t() | term()) :: {:ok, t()} | :error
  def parse(target) when target in @targets, do: {:ok, target}

  def parse(target) when is_binary(target) do
    case Enum.find(@targets, &(Atom.to_string(&1) == target)) do
      nil -> :error
      parsed -> {:ok, parsed}
    end
  end

  def parse(_target), do: :error

  @doc "Like `parse/1`, but for a value already known to be valid."
  @spec parse!(String.t() | term()) :: t()
  def parse!(target) do
    case parse(target) do
      {:ok, parsed} -> parsed
      :error -> target
    end
  end

  @doc """
  Whether this target is one of the ones the back office offers.

  An empty string is allowed through: it is the "not set" case, not a bad value.
  """
  @spec valid?(String.t() | nil) :: boolean()
  def valid?(target) when target in [nil, ""], do: true
  def valid?(target) when is_binary(target), do: parse(target) != :error
  def valid?(_target), do: false
end
