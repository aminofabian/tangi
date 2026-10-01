defmodule ViewNinjas.Accounts.Phone do
  @moduledoc """
  One phone normalizer, shared forever (build-plan.md M1).

  Every Kenyan mobile number entering the system is collapsed to a single
  canonical form — `2547XXXXXXXX` or `2541XXXXXXXX`, twelve digits with no
  `+`, spaces or punctuation:

      iex> ViewNinjas.Accounts.Phone.normalize("0712345678")
      {:ok, "254712345678"}

      iex> ViewNinjas.Accounts.Phone.normalize("+254 712 345 678")
      {:ok, "254712345678"}

      iex> ViewNinjas.Accounts.Phone.normalize("254712345678")
      {:ok, "254712345678"}

      iex> ViewNinjas.Accounts.Phone.normalize("712345678")
      {:ok, "254712345678"}

  The same module is reused verbatim by SMS (M2), Malipo (M7) and the
  supplier flows, so it is written once and tested hard. Numbers that do not
  look like a Kenyan mobile return `{:error, :invalid_phone}` rather than a
  best guess.
  """

  @type t :: String.t()

  @doc """
  Normalizes a phone number to its canonical `254…` form.

  Returns `{:ok, canonical}` or `{:error, :invalid_phone}`.
  """
  @spec normalize(term()) :: {:ok, t()} | {:error, :invalid_phone}
  def normalize(phone) when is_binary(phone) do
    cleaned =
      phone
      |> String.replace(~r/[^\d+]/, "")
      |> strip_international_prefix()

    if cleaned == "" do
      {:error, :invalid_phone}
    else
      canonicalize(cleaned)
    end
  end

  def normalize(_), do: {:error, :invalid_phone}

  @doc """
  Returns the canonical form, or the input unchanged when it cannot be
  normalized. Handy for display paths that must never crash.

      iex> ViewNinjas.Accounts.Phone.normalize_or_self("0712 345 678")
      "254712345678"

      iex> ViewNinjas.Accounts.Phone.normalize_or_self("not a phone")
      "not a phone"
  """
  @spec normalize_or_self(term()) :: term()
  def normalize_or_self(phone) do
    case normalize(phone) do
      {:ok, canonical} -> canonical
      {:error, :invalid_phone} -> phone
    end
  end

  @doc """
  Whether the given value is a valid Kenyan mobile number.

      iex> ViewNinjas.Accounts.Phone.valid?("0712345678")
      true

      iex> ViewNinjas.Accounts.Phone.valid?("12345")
      false
  """
  @spec valid?(term()) :: boolean()
  def valid?(phone), do: match?({:ok, _}, normalize(phone))

  @doc """
  Formats a phone number for display, `+254 712 345 678`. Anything that cannot
  be normalized is returned unchanged, so the function can sit in a template
  without a guard.

      iex> ViewNinjas.Accounts.Phone.format("254712345678")
      "+254 712 345 678"

      iex> ViewNinjas.Accounts.Phone.format("0712 345 678")
      "+254 712 345 678"

      iex> ViewNinjas.Accounts.Phone.format("not a phone")
      "not a phone"
  """
  @spec format(term()) :: term()
  def format(phone) do
    case normalize(phone) do
      {:ok, <<"254", a::binary-size(3), b::binary-size(3), c::binary-size(3)>>} ->
        "+254 #{a} #{b} #{c}"

      _ ->
        phone
    end
  end

  @doc """
  The Kenyan mobile network a number sits on, or `nil` when we cannot say.

  Airtime reaches all of them, so this is only ever a label: it tells the customer
  which network they are topping up. The ranges are the published national
  prefixes, and a valid number that falls outside them — Equitel, for one — comes
  back `nil` rather than as a guess.

      iex> ViewNinjas.Accounts.Phone.network("0712 345 678")
      :safaricom

      iex> ViewNinjas.Accounts.Phone.network("0733 000 222")
      :airtel

      iex> ViewNinjas.Accounts.Phone.network("0770 000 111")
      :telkom

      iex> ViewNinjas.Accounts.Phone.network("0747 000 111")
      :faiba

      iex> ViewNinjas.Accounts.Phone.network("0763 000 111")
      nil

      iex> ViewNinjas.Accounts.Phone.network("nonsense")
      nil
  """
  @spec network(term()) :: atom() | nil
  def network(phone) do
    case normalize(phone) do
      {:ok, <<"254", prefix::binary-size(3), _rest::binary>>} -> network_for(prefix)
      _ -> nil
    end
  end

  @doc """
  Every network airtime reaches, in the order a legend should show them.

      iex> ViewNinjas.Accounts.Phone.networks()
      [:safaricom, :airtel, :telkom, :faiba]
  """
  @spec networks() :: [atom()]
  def networks, do: [:safaricom, :airtel, :telkom, :faiba]

  @doc """
  The display name of a network, or `nil` for anything else.

      iex> ViewNinjas.Accounts.Phone.network_name(:safaricom)
      "Safaricom"

      iex> ViewNinjas.Accounts.Phone.network_name(nil)
      nil
  """
  @spec network_name(atom() | nil) :: String.t() | nil
  def network_name(:safaricom), do: "Safaricom"
  def network_name(:airtel), do: "Airtel"
  def network_name(:telkom), do: "Telkom"
  def network_name(:faiba), do: "Faiba"
  def network_name(_), do: nil

  # -- internals ---------------------------------------------------------

  # The published national prefix ranges, keyed on the three digits that follow
  # `254`. Faiba (Jamii Telecommunications) holds a single range, which is why the
  # match is three digits and not two. Equitel (0763–0769) is deliberately absent:
  # we would rather show nothing than the wrong network.
  @network_ranges [
    {:safaricom, 700, 729},
    {:safaricom, 740, 743},
    {:safaricom, 790, 799},
    {:safaricom, 110, 119},
    {:airtel, 730, 739},
    {:airtel, 750, 756},
    {:airtel, 780, 789},
    {:airtel, 100, 109},
    {:telkom, 770, 779},
    {:telkom, 120, 129},
    {:faiba, 747, 747}
  ]

  defp network_for(prefix) do
    prefix = String.to_integer(prefix)

    Enum.find_value(@network_ranges, fn {network, from, to} ->
      if prefix >= from and prefix <= to, do: network
    end)
  end

  defp strip_international_prefix("+" <> rest), do: strip_double_zero(rest)
  defp strip_international_prefix(digits), do: strip_double_zero(digits)

  # `00254…` is a valid way to write an international number in Kenya.
  defp strip_double_zero("00" <> rest), do: rest
  defp strip_double_zero(digits), do: digits

  # Already international: 254 + nine digits starting 7 or 1.
  defp canonicalize("254" <> rest = digits) when byte_size(rest) == 9 do
    if local?(rest), do: {:ok, digits}, else: {:error, :invalid_phone}
  end

  defp canonicalize("254" <> _), do: {:error, :invalid_phone}

  # Local with a leading zero: 07…/01… (ten digits) -> 254…
  defp canonicalize("0" <> rest) when byte_size(rest) == 9 do
    if local?(rest), do: {:ok, "254" <> rest}, else: {:error, :invalid_phone}
  end

  defp canonicalize("0" <> _), do: {:error, :invalid_phone}

  # Bare subscriber number: 7…/1… (nine digits) -> 254…
  defp canonicalize(digits) when byte_size(digits) == 9 do
    if local?(digits), do: {:ok, "254" <> digits}, else: {:error, :invalid_phone}
  end

  defp canonicalize(_), do: {:error, :invalid_phone}

  # Nine digits, mobile prefix 7 (07xx / 01xx are the Kenyan mobile ranges).
  defp local?(rest), do: String.match?(rest, ~r/^[71]\d{8}$/)
end
