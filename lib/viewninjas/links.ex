defmodule ViewNinjas.Links do
  @moduledoc """
  The one gate for customer-supplied links (scope.md §13).

  A link is stored and later sent to a panel, so it is treated as untrusted:
  trimmed, length-limited, and restricted to `https`. We never fetch it
  ourselves, so there is no server-side request to forge (no SSRF surface) —
  this only decides whether we are willing to store and forward it.
  """

  @max_length 300
  @schemes ~w(https)

  @doc "The longest link we will accept."
  @spec max_length() :: pos_integer()
  def max_length, do: @max_length

  @doc "The link schemes we allow."
  @spec schemes() :: [String.t()]
  def schemes, do: @schemes

  @doc """
  Validates and normalizes a link.

      iex> ViewNinjas.Links.validate("https://instagram.com/viewninjas")
      {:ok, "https://instagram.com/viewninjas"}

      iex> ViewNinjas.Links.validate("http://instagram.com/viewninjas")
      {:error, "The link must start with https://"}

      iex> ViewNinjas.Links.validate("instagram.com/viewninjas")
      {:error, "The link must start with https://"}

      iex> ViewNinjas.Links.validate("not a link")
      {:error, "That does not look like a link."}
  """
  @spec validate(String.t() | nil) :: {:ok, String.t()} | {:error, String.t()}
  def validate(value) when is_binary(value) do
    link = String.trim(value)

    cond do
      link == "" ->
        {:error, "Enter the link you want us to grow."}

      String.length(link) > @max_length ->
        {:error, "That link is longer than #{@max_length} characters."}

      true ->
        validate_uri(link)
    end
  end

  def validate(_value), do: {:error, "Enter the link you want us to grow."}

  @doc "Whether a link passes the gate."
  @spec valid?(String.t() | nil) :: boolean()
  def valid?(value), do: match?({:ok, _}, validate(value))

  defp validate_uri(link) do
    case URI.new(link) do
      {:ok, %URI{scheme: scheme, host: host}}
      when scheme in @schemes and is_binary(host) and host != "" ->
        {:ok, link}

      {:ok, %URI{scheme: scheme}} when scheme not in @schemes ->
        {:error, "The link must start with https://"}

      _ ->
        {:error, "That does not look like a link."}
    end
  end
end
