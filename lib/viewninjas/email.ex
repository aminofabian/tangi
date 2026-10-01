defmodule ViewNinjas.Email do
  @moduledoc """
  Sending transactional email through Resend.

  The API key is the super-admin's, held in `Settings` and encrypted at rest, so
  it is read **per send** rather than baked into the boot config: saving a new key
  in the back office takes effect on the next email, with no redeploy. The boot
  config (a Mailgun key in the environment, or Swoosh's `Local` adapter in
  development) is the fallback when no Resend key is set, so a deployment without
  one still sends.

  `deliver/2` merges this configuration **last**, which is what lets it win over
  the adapter chosen at boot — Swoosh merges per-deliver config after both the
  module and the application config.
  """

  require Logger

  alias ViewNinjas.Mailer
  alias ViewNinjas.Settings

  @doc """
  Delivers an email through Resend.

  Returns `{:error, :email_not_configured}` when no Resend key is in force, rather
  than raising, so a worker can treat a missing key the way it treats a missing SMS
  key: log it and let the application be the record.
  """
  @spec deliver(Swoosh.Email.t()) :: {:ok, term()} | {:error, term()}
  def deliver(%Swoosh.Email{} = email) do
    if resend_ready?() do
      Mailer.deliver(email, resend_config())
    else
      # Nothing to send with. Rather than fail the job, fall back to whatever the
      # boot config chose — in development that prints the email, which is the
      # point of the Local adapter.
      Mailer.deliver(email)
    end
  end

  @doc """
  Delivers an email and reports whether it went out, logging the reason if not.

  This is the shape the notification workers want: a failure is recorded rather
  than raised, because a receipt that cannot be emailed must not roll back a paid
  order.
  """
  @spec deliver!({String.t(), Swoosh.Email.t()}) :: :ok
  def deliver!({_label, %Swoosh.Email{} = email}) do
    case deliver(email) do
      {:ok, _metadata} ->
        :ok

      {:error, reason} ->
        Logger.warning("email not sent: #{inspect(reason)}")
        :ok
    end
  end

  defp resend_config do
    [
      adapter: Swoosh.Adapters.Resend,
      api_key: Settings.resend_api_key(),
      base_url: Settings.resend_base_url()
    ]
  end

  # Resend needs both a key and an HTTP API client. Swoosh's API clients are
  # disabled outside production (`api_client: false`), so a key saved in a
  # development database would otherwise call `false.post/4` and crash. Asking
  # both questions keeps the fall-back honest.
  defp resend_ready?, do: Settings.email_configured?() and api_client?()

  defp api_client? do
    case Application.get_env(:swoosh, :api_client) do
      nil -> false
      false -> false
      _client -> true
    end
  end
end
