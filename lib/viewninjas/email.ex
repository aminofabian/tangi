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

  With no Resend key in force this falls back to the adapter chosen at boot, which
  in development is Swoosh's `Local` adapter — so a developer can read the message
  without a key. Use `test_email/1` when the point is to prove Resend itself works.
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
  Sends a short diagnostic email to `recipient`, to check the Resend key really works.

  Unlike `deliver/1` this **never falls back**: it returns
  `{:error, :email_not_configured}` when no key is set, because a send that
  quietly succeeded through the local adapter would tell the super-admin their key
  is fine when Resend has never been contacted.

  Resend's own refusals are returned as `{:error, {status, message}}`, so the
  caller can show what was actually wrong rather than a generic failure.
  """
  @spec test_email(String.t()) :: {:ok, term()} | {:error, term()}
  def test_email(recipient) when is_binary(recipient) and recipient != "" do
    if resend_ready?() do
      Mailer.deliver(test_message(recipient), resend_config())
    else
      {:error, :email_not_configured}
    end
  end

  def test_email(_recipient), do: {:error, :no_recipient}

  @doc """
  The diagnostic message `test_email/1` sends, exposed so its recipient and sender
  can be asserted on without a network call.
  """
  @spec test_message(String.t()) :: Swoosh.Email.t()
  def test_message(recipient) do
    Swoosh.Email.new()
    |> Swoosh.Email.to(recipient)
    |> Swoosh.Email.from(Settings.mailer_from())
    |> Swoosh.Email.subject("Tangi — test email")
    |> Swoosh.Email.text_body("""
    This is a test from Tangi's settings screen.

    If you are reading it, the Resend API key is working and transactional email
    (order receipts, password resets, magic links) is going out.
    """)
  end

  @doc """
  Turns a delivery failure into something worth showing an operator.

  Swoosh returns Resend's refusals as `{status, body}`; a transport failure comes
  back as an exception struct. Both are flattened to one line here, because the
  audience is a super-admin staring at a button, not a log parser.
  """
  @spec failure_reason(term()) :: String.t()
  def failure_reason({status, %{"message" => message}}) when is_binary(message) do
    "#{status} — #{message}"
  end

  def failure_reason({status, _body}) when is_integer(status), do: "HTTP #{status}"
  def failure_reason(:email_not_configured), do: "no Resend API key is set"
  def failure_reason(:no_recipient), do: "no address to send to"
  def failure_reason(%{__exception__: true} = exception), do: Exception.message(exception)
  def failure_reason(other), do: inspect(other)

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

  @doc """
  Whether Resend is genuinely ready to send: a key **and** an HTTP API client.

  This is what the back office keys its "send a test email" button off, so the
  button is never enabled for a deployment that would silently fall back to the
  local adapter.
  """
  @spec configured?() :: boolean()
  def configured?, do: resend_ready?()

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
