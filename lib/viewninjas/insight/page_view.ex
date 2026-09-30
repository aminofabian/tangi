defmodule ViewNinjas.Insight.PageView do
  @moduledoc """
  One page view, first-party and PII-free (scope.md §6, §13).

  Append-only: no third-party script, no cookie, and no IP — just a
  `visitor_hash` that rotates daily, the path, the referrer and any `utm_*`
  that arrived with it. Written from M6; read by the traffic panel in M10.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ViewNinjas.Accounts.User

  @type t :: %__MODULE__{}

  @device_classes ~w(mobile tablet desktop other)

  schema "page_views" do
    belongs_to :user, User
    field :at, :utc_datetime
    field :path, :string
    field :referrer, :string
    field :utm_source, :string
    field :utm_medium, :string
    field :utm_campaign, :string
    field :visitor_hash, :string
    field :device_class, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "The device classes a view can carry."
  @spec device_classes() :: [String.t()]
  def device_classes, do: @device_classes

  def changeset(page_view, attrs) do
    page_view
    |> cast(attrs, [
      :at,
      :path,
      :referrer,
      :utm_source,
      :utm_medium,
      :utm_campaign,
      :visitor_hash,
      :device_class
    ])
    |> validate_required([:at, :path])
    |> validate_inclusion(:device_class, @device_classes)
  end
end
