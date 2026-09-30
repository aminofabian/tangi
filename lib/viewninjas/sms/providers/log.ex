defmodule ViewNinjas.Sms.Providers.Log do
  @moduledoc """
  Development provider: writes the message to the log instead of sending it, so
  an OTP is visible locally without an SMS account.

  Never configure this in production — it would put OTPs in the logs.
  """
  @behaviour ViewNinjas.Sms.Provider

  require Logger

  @impl true
  def send_sms(to, body) do
    Logger.warning("[sms:log] to=#{to} body=#{body}")

    {:ok,
     %{
       provider_ref: "log-#{System.unique_integer([:positive])}",
       status: :sent,
       cost_micros: 0
     }}
  end
end
