defmodule ViewNinjas.Accounts.OtpChallenge do
  @moduledoc """
  A one-time code challenge for a phone number (build-plan.md M2).

  The plaintext code is never stored: `code_hash` is an HMAC of the code and
  the phone, keyed by the app secret. A challenge expires, locks after three
  wrong attempts, and is single use (`consumed_at`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "otp_challenges" do
    field :phone, :string
    field :code_hash, :binary
    field :purpose, Ecto.Enum, values: [:phone_verification], default: :phone_verification
    field :expires_at, :utc_datetime
    field :attempts, :integer, default: 0
    field :consumed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(challenge, attrs) do
    challenge
    |> cast(attrs, [:phone, :code_hash, :purpose, :expires_at])
    |> validate_required([:phone, :expires_at])
  end
end
