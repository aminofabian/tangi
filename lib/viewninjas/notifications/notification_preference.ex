defmodule ViewNinjas.Notifications.NotificationPreference do
  @moduledoc """
  One customer's wish about one channel (scope.md §11; build-plan.md M11).

  A row exists only once a customer has said something; until then the channel's
  default applies (both channels on, no quiet hours). `quiet_hours` is a
  `"HH:MM-HH:MM"` window in local time, or null for "any hour".
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ViewNinjas.Accounts.User

  @type t :: %__MODULE__{}

  @channels ~w(sms email)a

  schema "notification_preferences" do
    belongs_to :user, User

    field :channel, Ecto.Enum, values: @channels
    field :opted_in, :boolean, default: true
    field :quiet_hours, :string

    timestamps(type: :utc_datetime)
  end

  @doc "The channels a customer can be reached on."
  @spec channels() :: [atom()]
  def channels, do: @channels

  def changeset(preference, attrs) do
    preference
    |> cast(attrs, [:user_id, :channel, :opted_in, :quiet_hours])
    |> validate_required([:user_id, :channel, :opted_in])
    |> validate_format(:quiet_hours, ~r/^\d{2}:\d{2}-\d{2}:\d{2}$/,
      message: "looks like 21:00-07:00"
    )
    |> unique_constraint([:user_id, :channel])
  end
end
