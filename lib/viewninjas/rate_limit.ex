defmodule ViewNinjas.RateLimit do
  @moduledoc """
  Rate limiting, so a script cannot mass-create accounts or grind passwords
  (scope.md §13).

  Limits are per node and in memory (Hammer, ETS). They are the first line of
  defence, not the only one — the per-number and per-day caps for OTP and SMS
  land in M2. Keys are composed from the client IP *and* the identity being
  acted on, so a single IP spraying many numbers and many IPs hitting one
  number are both caught.

  Limits can be tightened per environment through the `:rate_limits`
  application env, and switched off entirely with `rate_limiting: false`
  (the test suite does this so unrelated cases do not share one budget).
  """

  use Hammer, backend: :ets

  # {window_ms, limit}
  @default_limits %{
    signup_ip: {60 * 60_000, 10},
    signup_phone: {60 * 60_000, 5},
    login_ip: {5 * 60_000, 20},
    login_identifier: {5 * 60_000, 10},
    otp_phone: {60 * 60_000, 5},
    otp_ip: {60 * 60_000, 10},
    # A script firing M-Pesa prompts is the abuse case that burns the key and the
    # name (scope.md §13), so payment creation is budgeted per customer and per
    # number as well.
    payment_user: {60 * 60_000, 20},
    payment_phone: {60 * 60_000, 10}
  }

  @doc """
  Sign-up: budgets both the client IP and the phone being signed up.
  """
  @spec allow_signup?(String.t(), String.t()) :: boolean()
  def allow_signup?(ip, phone) do
    allow?("signup:ip:#{ip}", :signup_ip) and allow?("signup:phone:#{phone}", :signup_phone)
  end

  @doc """
  Login: budgets both the client IP and the identifier (email or phone) being
  logged in.
  """
  @spec allow_login?(String.t(), String.t()) :: boolean()
  def allow_login?(ip, identifier) do
    allow?("login:ip:#{ip}", :login_ip) and
      allow?("login:identifier:#{identifier}", :login_identifier)
  end

  @doc """
  OTP requests: budgets both the number being messaged and the client IP, on
  top of the 60-second resend throttle that `PhoneVerification` enforces.
  """
  @spec allow_otp_request?(String.t(), String.t()) :: boolean()
  def allow_otp_request?(phone, ip) do
    allow?("otp:phone:#{phone}", :otp_phone) and allow?("otp:ip:#{ip}", :otp_ip)
  end

  @doc """
  Consumes one unit from `key` and reports whether it is still allowed under
  the named limit.
  """
  @spec allow?(term(), atom()) :: boolean()
  def allow?(key, limit_name) do
    {window_ms, limit} = limit(limit_name)
    check(key, window_ms, limit) == :ok
  end

  @doc """
  Returns `:ok` when `key` is under its limit, `{:error, :rate_limited}`
  otherwise. Always `:ok` when rate limiting is switched off.
  """
  @spec check(term(), pos_integer(), pos_integer()) :: :ok | {:error, :rate_limited}
  def check(key, window_ms, limit) do
    if enabled?() do
      case hit(key, window_ms, limit) do
        {:allow, _count} -> :ok
        {:deny, _retry_after_ms} -> {:error, :rate_limited}
      end
    else
      :ok
    end
  end

  @doc """
  The configured `{window_ms, limit}` for a named limit. Overridable per
  environment through the `:rate_limits` application env.

  A name that is neither configured nor a known default is a programmer error and
  is raised loudly, so a missing limit is never silently no limit.
  """
  @spec limit(atom()) :: {pos_integer(), pos_integer()}
  def limit(name) do
    configured = Map.get(Application.get_env(:viewninjas, :rate_limits, %{}), name)

    configured || Map.get(@default_limits, name) ||
      raise ArgumentError, "unknown rate limit: #{inspect(name)}"
  end

  defp enabled?, do: Application.get_env(:viewninjas, :rate_limiting, true)
end
