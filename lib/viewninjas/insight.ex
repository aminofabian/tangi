defmodule ViewNinjas.Insight do
  @moduledoc """
  First-party, PII-free analytics (scope.md §6, §13; build-plan.md M6).

  M6 only *collects*: one append-only `PageView` per page, with a
  `visitor_hash` built from a daily salt plus the request's address and user
  agent, truncated — so it is stable within a day, useless across days, and can
  never be reversed to a person. No third party, no cookie, no stored IP.

  Nothing reads these rows until the traffic panel in M10. A "checkout started"
  step has no page of its own, so it is recorded under the synthetic path
  `/offers/:id/checkout`; the funnel in §11 groups by path.

  The web layer extracts the request facts; this context only stores them.
  """

  import Ecto.Query

  require Logger

  alias ViewNinjas.Insight.PageView
  alias ViewNinjas.{Repo, Settings}

  @visitor_hash_length 32

  @doc """
  Records one page view. Best-effort: a failure is logged, never raised, so
  analytics can never break a page (scope.md §13).
  """
  @spec record_page_view(map()) :: :ok
  def record_page_view(attrs) do
    at = Map.get(attrs, :at, DateTime.utc_now(:second))
    utm = Map.get(attrs, :utm, %{})

    data = %{
      at: at,
      path: Map.get(attrs, :path),
      referrer: Map.get(attrs, :referrer),
      utm_source: utm["utm_source"],
      utm_medium: utm["utm_medium"],
      utm_campaign: utm["utm_campaign"],
      visitor_hash: visitor_hash(attrs[:ip], attrs[:user_agent], at),
      device_class: device_class(attrs[:user_agent])
    }

    %PageView{}
    |> PageView.changeset(data)
    |> Ecto.Changeset.put_change(:user_id, Map.get(attrs, :user_id))
    |> Repo.insert()
    |> case do
      {:ok, _page_view} ->
        :ok

      {:error, changeset} ->
        Logger.warning("page view not recorded: #{inspect(changeset.errors)}")
        :ok
    end
  end

  @doc "The page views, newest first."
  @spec list_page_views(pos_integer()) :: [PageView.t()]
  def list_page_views(limit \\ 50) do
    PageView
    |> order_by([p], desc: p.at, desc: p.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  A stable, non-reversible visitor id for one day.

  The salt is bucketed by date, so yesterday's hash and today's hash for the
  same person never match (scope.md §13). A missing address or agent still
  produces a hash; it is just shared by everyone in that bucket.
  """
  @spec visitor_hash(String.t() | nil, String.t() | nil, DateTime.t()) :: String.t()
  def visitor_hash(address, user_agent, %DateTime{} = at) do
    day = at |> DateTime.to_date() |> Date.to_iso8601()
    key = :crypto.hash(:sha256, "#{salt()}:#{day}")

    :crypto.mac(:hmac, :sha256, key, "#{address}|#{user_agent}")
    |> Base.encode16(case: :lower)
    |> binary_part(0, @visitor_hash_length)
  end

  @doc "A coarse device class from the user agent — a heuristic, not a promise."
  @spec device_class(String.t() | nil) :: String.t()
  def device_class(nil), do: "other"

  def device_class(user_agent) do
    cond do
      user_agent =~ ~r/iPad|Tablet/i -> "tablet"
      user_agent =~ ~r/Android(?!.*Mobile)/i -> "tablet"
      user_agent =~ ~r/Mobile|iPhone|Android/i -> "mobile"
      user_agent =~ ~r/Windows|Macintosh|Linux|CrOS/i -> "desktop"
      true -> "other"
    end
  end

  defp salt, do: Settings.insight_hash_salt()
end
