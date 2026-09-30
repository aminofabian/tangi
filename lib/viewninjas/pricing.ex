defmodule ViewNinjas.Pricing do
  @moduledoc """
  The retail price of a wholesale rate (scope.md §7), and the settings it is
  quoted from.

  One flat margin over landed cost, integer arithmetic throughout — no floats on
  either side of a price. Retail is the landed cost times `1 + margin`, and the
  buffer sits between cost and landed because the USD float is bought before the
  customer pays.

  The arithmetic is pure and takes a `Params` value object, so a quote is
  reproducible from a snapshot; `current/0` builds that object from the newest
  `Pricing.Settings` version and `Pricing.FxRate` row, falling back to the §7
  defaults when nothing has been recorded yet. Everything is append-only: a
  change to a knob is a new version, never an edit.

  The guardrail — a lane may not be published at or under landed-plus-buffer —
  lives in `ViewNinjas.Catalog.publish_lane/2`.
  """

  import Ecto.Query

  alias ViewNinjas.Accounts.User
  alias ViewNinjas.Pricing.{FxRate, Params, Settings}
  alias ViewNinjas.Repo

  @pubsub ViewNinjas.PubSub
  @topic "pricing"

  # -- the quote engine (pure) -------------------------------------------

  @doc """
  The retail price in KES cents for `quantity` units at `rate_ppm` USD per 1,000.

  Defaults to 1,000 units — the figure the catalog shows — and the §7 defaults
  for the knobs.

      iex> ViewNinjas.Pricing.retail_kes_cents(900_000)
      27_600
  """
  @spec retail_kes_cents(integer() | nil, integer(), Params.t()) :: integer() | nil
  def retail_kes_cents(rate_ppm, quantity \\ 1000, params \\ Params.defaults())

  def retail_kes_cents(nil, _quantity, _params), do: nil

  def retail_kes_cents(rate_ppm, quantity, params) when is_integer(rate_ppm) do
    rate_ppm
    |> cost_usd_ppm(quantity)
    |> cost_kes_ppm(params)
    |> landed_ppm(params)
    |> retail_ppm(params)
    |> round_to_shilling()
    |> Kernel.*(100)
  end

  @doc "`rate_ppm * quantity / 1000` — the cost of the units in micros of USD."
  @spec cost_usd_ppm(integer(), integer()) :: integer()
  def cost_usd_ppm(rate_ppm, quantity), do: div(rate_ppm * quantity, 1000)

  @doc "Landed in micros of KES: the USD cost converted at the FX rate."
  @spec cost_kes_ppm(integer(), Params.t()) :: integer()
  def cost_kes_ppm(cost_usd_ppm, params), do: div(cost_usd_ppm * params.fx_ppm, 1_000_000)

  @doc "Cost plus the buffer, in micros of KES. This is the floor a lane can price above."
  @spec landed_ppm(integer(), Params.t()) :: integer()
  def landed_ppm(cost_kes_ppm, params),
    do: div(cost_kes_ppm * (10_000 + params.buffer_bps), 10_000)

  @doc "Landed plus the margin, in micros of KES."
  @spec retail_ppm(integer(), Params.t()) :: integer()
  def retail_ppm(landed_ppm, params),
    do: div(landed_ppm * (10_000 + params.margin_bps), 10_000)

  @doc "Micros of KES to whole shillings, half up."
  @spec round_to_shilling(integer()) :: integer()
  def round_to_shilling(retail_ppm), do: div(retail_ppm + 500_000, 1_000_000)

  @doc "The landed cost in KES cents — the floor a lane's price must beat."
  @spec landed_kes_cents(integer() | nil, integer(), Params.t()) :: integer() | nil
  def landed_kes_cents(rate_ppm, quantity \\ 1000, params \\ Params.defaults())

  def landed_kes_cents(nil, _quantity, _params), do: nil

  def landed_kes_cents(rate_ppm, quantity, params) when is_integer(rate_ppm) do
    rate_ppm
    |> cost_usd_ppm(quantity)
    |> cost_kes_ppm(params)
    |> landed_ppm(params)
    |> round_to_shilling()
    |> Kernel.*(100)
  end

  @doc "A KES price as `KSh 1,250` — never `KES 1250.00`, never USD (scope.md §7)."
  @spec format_kes_cents(integer() | nil) :: String.t() | nil
  def format_kes_cents(nil), do: nil

  def format_kes_cents(cents) when is_integer(cents) do
    shillings = div(cents + 50, 100)

    "KSh " <>
      (shillings
       |> Integer.to_string()
       |> String.reverse()
       |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
       |> String.reverse())
  end

  @doc """
  The per-quantity selling price in KES cents, kept to the cent when rounding
  to a shilling would hide it.

  A `0.90` USD service is `KSh 276`. A `0.0012` USD view service is about
  `KSh 0.37` — `retail_kes_cents/3` rounds that to `KSh 0`, which reads as if
  the rate was never converted.
  """
  @spec display_kes_cents(integer() | nil, integer(), Params.t()) :: integer() | nil
  def display_kes_cents(rate_ppm, quantity \\ 1000, params \\ Params.defaults())

  def display_kes_cents(nil, _quantity, _params), do: nil

  def display_kes_cents(rate_ppm, quantity, params) when is_integer(rate_ppm) do
    case retail_kes_cents(rate_ppm, quantity, params) do
      cents when is_integer(cents) and cents >= 100 ->
        cents

      _ ->
        exact_retail_cents(rate_ppm, quantity, params)
    end
  end

  @doc """
  Formats a selling price. Whole shillings from one shilling up; cents below
  that, so a sub-shilling quote stays visible.
  """
  @spec format_selling_cents(integer() | nil) :: String.t() | nil
  def format_selling_cents(nil), do: nil

  def format_selling_cents(cents) when is_integer(cents) and cents >= 100,
    do: format_kes_cents(cents)

  def format_selling_cents(cents) when is_integer(cents) and cents > 0 do
    whole = div(cents, 100)
    frac = cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "KSh #{whole}.#{frac}"
  end

  def format_selling_cents(cents) when is_integer(cents), do: format_kes_cents(cents)

  @doc """
  Whether the flat-margin quote sits strictly above landed cost.

  Compared before shilling rounding, so a view service whose landed cost and
  retail both round to KSh 0 is still a real price and can be published.
  """
  @spec beats_landed?(integer() | nil, Params.t()) :: boolean()
  def beats_landed?(rate_ppm, params \\ Params.defaults())

  def beats_landed?(rate_ppm, params) when is_integer(rate_ppm) and rate_ppm > 0 do
    landed =
      rate_ppm
      |> cost_usd_ppm(1000)
      |> cost_kes_ppm(params)
      |> landed_ppm(params)

    retail_ppm(landed, params) > landed
  end

  def beats_landed?(_rate_ppm, _params), do: false

  defp exact_retail_cents(rate_ppm, quantity, params) do
    ppm =
      rate_ppm
      |> cost_usd_ppm(quantity)
      |> cost_kes_ppm(params)
      |> landed_ppm(params)
      |> retail_ppm(params)

    cents = div(ppm + 5_000, 10_000)
    if ppm > 0 and cents == 0, do: 1, else: cents
  end

  # -- the settings in force ---------------------------------------------

  @doc """
  The parameters the pricer quotes from: the newest settings version and FX
  rate, or the §7 defaults when nothing has been recorded.
  """
  @spec current() :: Params.t()
  def current, do: Settings.to_params(current_settings(), current_fx())

  @doc "The newest settings version, or nil when none exists yet."
  @spec current_settings() :: Settings.t() | nil
  def current_settings do
    Settings
    |> order_by([s], desc: s.effective_at, desc: s.id)
    |> limit(1)
    |> preload(:actor)
    |> Repo.one()
  end

  @doc "Fetches one settings version by id."
  def get_settings!(id), do: Repo.get!(Settings, id)

  @doc "The newest recorded FX rate, or nil."
  @spec current_fx() :: FxRate.t() | nil
  def current_fx do
    FxRate
    |> order_by([f], desc: f.fetched_at, desc: f.id)
    |> limit(1)
    |> preload(:actor)
    |> Repo.one()
  end

  @doc "Fetches one recorded FX rate by id."
  def get_fx_rate!(id), do: Repo.get!(FxRate, id)

  @doc "The effective FX in micros of KES per USD."
  @spec fx_ppm() :: Params.fx_ppm()
  def fx_ppm, do: current().fx_ppm

  @doc "The effective margin in basis points."
  @spec margin_bps() :: integer()
  def margin_bps, do: current().margin_bps

  @doc "The effective buffer in basis points."
  @spec buffer_bps() :: integer()
  def buffer_bps, do: current().buffer_bps

  @doc "The settings versions, newest first."
  @spec list_settings(pos_integer()) :: [Settings.t()]
  def list_settings(limit \\ 20) do
    Settings
    |> order_by([s], desc: s.effective_at, desc: s.id)
    |> limit(^limit)
    |> preload(:actor)
    |> Repo.all()
  end

  def change_settings(%Settings{} = settings, attrs \\ %{}) do
    Settings.changeset(settings, attrs)
  end

  @doc """
  Appends a new settings version; nothing is edited in place (scope.md §6).

  `attrs` are atom-keyed and may include `:margin_bps`, `:buffer_bps`,
  `:fx_override_ppm`, `:rounding`, `:reason` and `:effective_at` (defaults to
  now). The actor is recorded for the audit trail.
  """
  @spec append_settings(map(), User.t() | nil) ::
          {:ok, Settings.t()} | {:error, Ecto.Changeset.t()}
  def append_settings(attrs, actor) do
    attrs =
      attrs
      |> Enum.into(%{})
      |> Map.put_new(:effective_at, DateTime.utc_now(:second))

    %Settings{}
    |> Settings.changeset(attrs)
    |> Ecto.Changeset.put_change(:actor_id, actor && actor.id)
    |> Repo.insert()
    |> announce()
  end

  @doc "The recorded FX rates, newest first."
  @spec list_fx_rates(pos_integer()) :: [FxRate.t()]
  def list_fx_rates(limit \\ 20) do
    FxRate
    |> order_by([f], desc: f.fetched_at, desc: f.id)
    |> limit(^limit)
    |> preload(:actor)
    |> Repo.all()
  end

  def change_fx_rate(%FxRate{} = fx_rate, attrs \\ %{}) do
    FxRate.changeset(fx_rate, attrs)
  end

  @doc """
  Records an FX rate — from the daily job (`actor` nil) or a super-admin.

  `attrs` are atom-keyed and may include `:rate_ppm`, `:source` (`"daily"` |
  `"manual"` | `"fixture"`) and `:fetched_at` (defaults to now).
  """
  @spec record_fx_rate(map(), User.t() | nil) ::
          {:ok, FxRate.t()} | {:error, Ecto.Changeset.t()}
  def record_fx_rate(attrs, actor) do
    attrs =
      attrs
      |> Enum.into(%{})
      |> Map.put_new(:fetched_at, DateTime.utc_now(:second))

    %FxRate{}
    |> FxRate.changeset(attrs)
    |> Ecto.Changeset.put_change(:actor_id, actor && actor.id)
    |> Repo.insert()
    |> announce()
  end

  # -- pubsub ------------------------------------------------------------

  @doc "Subscribes the caller to pricing changes, so a screen can re-quote."
  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, @topic)

  # A change to the knobs or the rate re-quotes every screen that is listening.
  defp announce({:ok, _record} = ok) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:pricing, :changed})
    ok
  end

  defp announce(error), do: error
end
