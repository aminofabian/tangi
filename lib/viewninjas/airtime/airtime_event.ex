defmodule ViewNinjas.Airtime.AirtimeEvent do
  @moduledoc """
  An append-only line in one airtime order's timeline (scope: §5). Written by the
  same transitions that move the order, so support can read what happened without
  reconstructing it from timestamps.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ViewNinjas.Accounts.User
  alias ViewNinjas.Airtime.AirtimeOrder

  @type t :: %__MODULE__{}

  schema "airtime_events" do
    belongs_to :airtime_order, AirtimeOrder
    belongs_to :actor, User

    field :from_state, :string
    field :to_state, :string
    field :reason, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "A changeset for one state-change record."
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:airtime_order_id, :from_state, :to_state, :reason, :actor_id])
    |> validate_required([:airtime_order_id, :to_state])
    |> foreign_key_constraint(:airtime_order_id)
  end
end
