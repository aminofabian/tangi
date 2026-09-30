defmodule ViewNinjas.Sms.SmsMessage do
  @moduledoc """
  One outbound SMS (build-plan.md M2, scope.md §6).

  The body is deliberately not stored: for an OTP it is a secret, and for a
  notification this row is a delivery and cost record, not a message archive.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @statuses [:queued, :sent, :delivered, :failed]

  schema "sms_messages" do
    field :to, :string
    field :template, :string
    field :provider, :string
    field :provider_ref, :string
    field :status, Ecto.Enum, values: @statuses, default: :queued
    # Micros of KES, so the daily spend cap stays in integers.
    field :cost_micros, :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:to, :template, :provider, :status, :provider_ref, :cost_micros])
    |> validate_required([:to, :template, :provider])
  end
end
