defmodule ViewNinjas.Workers.DeliverOtp do
  @moduledoc """
  Generates a phone-verification code and sends it (build-plan.md M2).

  The code is created here, stored only as a hash on the challenge, and sent by
  SMS — so it never lands in the jobs table, the database, or production logs.
  Outbound HTTP happens in a worker, never in a rendered page (scope.md §13).
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias ViewNinjas.Accounts.{OtpChallenge, PhoneVerification}
  alias ViewNinjas.Repo
  alias ViewNinjas.Sms

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"challenge_id" => id}}) do
    case Repo.get(OtpChallenge, id) do
      nil -> :ok
      challenge -> deliver(challenge)
    end
  end

  defp deliver(%OtpChallenge{consumed_at: consumed}) when not is_nil(consumed), do: :ok

  defp deliver(%OtpChallenge{} = challenge) do
    if expired?(challenge) do
      :ok
    else
      code = PhoneVerification.generate_code()
      {:ok, _challenge} = PhoneVerification.put_code(challenge, code)
      send_code(challenge.phone, code)
    end
  end

  defp send_code(phone, code) do
    case Sms.send_message(%{to: phone, template: "phone_verification", body: body(code)}) do
      {:ok, _message} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp expired?(challenge),
    do: DateTime.compare(challenge.expires_at, DateTime.utc_now(:second)) == :lt

  defp body(code),
    do: "Your Tangi code is #{code}. It expires in 5 minutes. Never share it."
end
