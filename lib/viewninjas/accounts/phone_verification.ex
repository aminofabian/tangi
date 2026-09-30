defmodule ViewNinjas.Accounts.PhoneVerification do
  @moduledoc """
  Proving the phone on an account (build-plan.md M2).

  A 6-digit code, five minutes to live, at most three attempts, a 60-second
  resend throttle, and per-number and per-IP caps. Codes are single use, and
  the plaintext never touches the database: the challenge stores an HMAC of the
  code and the phone, and the `DeliverOtp` worker generates and sends the code,
  so the secret lives only in memory and in the SMS.
  """
  import Ecto.Query

  require Logger

  alias ViewNinjas.Accounts.{OtpChallenge, Phone, User}
  alias ViewNinjas.RateLimit
  alias ViewNinjas.Repo
  alias ViewNinjas.Workers.DeliverOtp

  @ttl_minutes 5
  @max_attempts 3
  @resend_seconds 60

  @doc """
  Queues a code for the user's phone.

  Applies, in order: the phone must be valid, the 60-second resend throttle,
  and the per-number and per-IP caps. The send itself happens in the worker.
  """
  @spec request(User.t(), keyword()) :: {:ok, :queued} | {:error, atom()}
  def request(%User{} = user, opts \\ []) do
    ip = Keyword.get(opts, :ip, "unknown")

    cond do
      not Phone.valid?(user.phone) ->
        {:error, :invalid_phone}

      throttled?(user.phone) ->
        {:error, :too_soon}

      not RateLimit.allow_otp_request?(user.phone, ip) ->
        {:error, :rate_limited}

      true ->
        enqueue(user.phone)
    end
  end

  @doc """
  Checks a code against the freshest challenge for the user's phone.

  Returns `{:ok, user}` with `phone_verified_at` set on success. Every failure
  is a distinct reason so the screen can say something true.
  """
  @spec verify(User.t(), String.t()) :: {:ok, User.t()} | {:error, atom()}
  def verify(%User{} = user, code) when is_binary(code) do
    challenge = latest_challenge(user.phone)

    cond do
      is_nil(challenge) ->
        {:error, :no_challenge}

      challenge.consumed_at ->
        {:error, :already_used}

      expired?(challenge) ->
        {:error, :expired}

      challenge.attempts >= @max_attempts ->
        {:error, :too_many_attempts}

      is_nil(challenge.code_hash) ->
        {:error, :no_code}

      Plug.Crypto.secure_compare(challenge.code_hash, code_hash(code, challenge.phone)) ->
        consume(user, challenge)

      true ->
        register_failed_attempt(challenge)
    end
  end

  def verify(_user, _code), do: {:error, :invalid_code}

  @doc "Six random digits, as a string."
  @spec generate_code() :: String.t()
  def generate_code do
    4
    |> :crypto.strong_rand_bytes()
    |> :binary.decode_unsigned()
    |> rem(1_000_000)
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
  end

  @doc "Stores the HMAC of `code` on the challenge. Called by the worker."
  @spec put_code(OtpChallenge.t(), String.t()) :: {:ok, OtpChallenge.t()}
  def put_code(challenge, code) do
    challenge
    |> Ecto.Changeset.change(code_hash: code_hash(code, challenge.phone))
    |> Repo.update()
  end

  # -- internals ---------------------------------------------------------

  defp enqueue(phone) do
    changeset =
      %OtpChallenge{}
      |> OtpChallenge.changeset(%{
        phone: phone,
        purpose: :phone_verification,
        expires_at: DateTime.add(DateTime.utc_now(:second), @ttl_minutes * 60, :second)
      })
      |> Repo.insert()

    with {:ok, challenge} <- changeset,
         {:ok, _job} <- Oban.insert(DeliverOtp.new(%{"challenge_id" => challenge.id})) do
      {:ok, :queued}
    else
      {:error, _reason} -> {:error, :enqueue_failed}
    end
  end

  defp throttled?(phone) do
    cutoff = DateTime.add(DateTime.utc_now(:second), -@resend_seconds, :second)
    Repo.exists?(from c in OtpChallenge, where: c.phone == ^phone and c.inserted_at > ^cutoff)
  end

  defp latest_challenge(phone) do
    Repo.one(
      from c in OtpChallenge,
        where: c.phone == ^phone,
        order_by: [desc: c.inserted_at, desc: c.id],
        limit: 1
    )
  end

  defp expired?(challenge),
    do: DateTime.compare(challenge.expires_at, DateTime.utc_now(:second)) == :lt

  defp register_failed_attempt(challenge) do
    attempts = challenge.attempts + 1
    {:ok, _} = challenge |> Ecto.Changeset.change(attempts: attempts) |> Repo.update()

    if attempts >= @max_attempts do
      Logger.warning("OTP lockout: #{challenge.phone} locked after #{attempts} failed attempts")

      {:error, :too_many_attempts}
    else
      {:error, :invalid_code}
    end
  end

  defp consume(user, challenge) do
    now = DateTime.utc_now(:second)

    # Single use: retire every open challenge for this number as we verify.
    Repo.transact(fn ->
      from(c in OtpChallenge, where: c.phone == ^challenge.phone and is_nil(c.consumed_at))
      |> Repo.update_all(set: [consumed_at: now])

      {:ok, user} =
        user
        |> Ecto.Changeset.change(phone_verified_at: now)
        |> Repo.update()

      {:ok, user}
    end)
  end

  defp code_hash(code, phone), do: :crypto.mac(:hmac, :sha256, pepper(), "#{phone}:#{code}")

  # The key is the app secret, so a database dump cannot be brute-forced back
  # into a live code. Falls back to a fixed value only in the unlikely case
  # that no secret is configured (development).
  defp pepper do
    Application.get_env(:viewninjas, :otp_pepper) ||
      case get_in(Application.get_env(:viewninjas, ViewNinjasWeb.Endpoint) || [], [
             :secret_key_base
           ]) do
        secret when is_binary(secret) -> secret
        _ -> "viewninjas-otp-pepper"
      end
  end
end
