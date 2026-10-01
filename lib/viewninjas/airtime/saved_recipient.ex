defmodule ViewNinjas.Airtime.SavedRecipient do
  @moduledoc """
  A phone number a customer keeps for future airtime buys (scope: §8).

  One number is saved once per customer — the unique index says so — so picking it
  twice never duplicates it. `label` is what the customer calls it ("Mum"), and
  `last_used_at` lets the picker show the most recent first.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ViewNinjas.Accounts.User

  @type t :: %__MODULE__{}

  schema "saved_recipients" do
    belongs_to :user, User

    field :phone, :string
    field :label, :string
    field :last_used_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "A changeset for one saved number."
  def changeset(recipient, attrs) do
    recipient
    |> cast(attrs, [:user_id, :phone, :label, :last_used_at])
    |> validate_required([:user_id, :phone])
    |> unique_constraint([:user_id, :phone])
    |> foreign_key_constraint(:user_id)
  end
end
