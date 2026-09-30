defmodule ViewNinjas.Accounts.PhoneVerificationTest do
  use ViewNinjas.DataCase, async: true

  use Oban.Testing, repo: ViewNinjas.Repo

  import ViewNinjas.AccountsFixtures

  alias ViewNinjas.Accounts
  alias ViewNinjas.Accounts.{OtpChallenge, PhoneVerification}
  alias ViewNinjas.RateLimit
  alias ViewNinjas.Sms.Providers.Test, as: SmsOutbox
  alias ViewNinjas.Workers.DeliverOtp

  setup do
    %{user: user_fixture()}
  end

  describe "request/2" do
    test "queues a code without storing any plaintext", %{user: user} do
      assert {:ok, :queued} = PhoneVerification.request(user)

      challenge = Repo.one(OtpChallenge)
      assert challenge.phone == user.phone
      assert is_nil(challenge.code_hash)
      assert_enqueued(worker: DeliverOtp, args: %{"challenge_id" => challenge.id})
    end

    test "throttles a second request within 60 seconds", %{user: user} do
      assert {:ok, :queued} = PhoneVerification.request(user)
      assert PhoneVerification.request(user) == {:error, :too_soon}
    end

    test "allows a resend once the window has passed", %{user: user} do
      assert {:ok, :queued} = PhoneVerification.request(user)
      age_challenges()

      assert {:ok, :queued} = PhoneVerification.request(user)
    end

    test "is refused per number once the budget is gone", %{user: user} do
      exhaust(:otp_phone, "otp:phone:#{user.phone}")

      assert PhoneVerification.request(user) == {:error, :rate_limited}
    end

    test "is refused per IP once the budget is gone", %{user: user} do
      exhaust(:otp_ip, "otp:ip:203.0.113.7")

      assert PhoneVerification.request(user, ip: "203.0.113.7") == {:error, :rate_limited}
    end

    test "rejects a number that cannot receive texts" do
      user = %{user_fixture() | phone: "12345"}

      assert PhoneVerification.request(user) == {:error, :invalid_phone}
    end
  end

  describe "verify/2" do
    setup %{user: user} do
      {:ok, :queued} = PhoneVerification.request(user)
      [job] = all_enqueued(worker: DeliverOtp)
      :ok = perform_job(DeliverOtp, job.args)

      %{code: SmsOutbox.last_code(user.phone)}
    end

    test "verifies with the right code and marks the phone verified", %{user: user, code: code} do
      assert code

      assert {:ok, verified} = PhoneVerification.verify(user, code)
      assert verified.phone_verified_at
      assert Accounts.get_user!(user.id).phone_verified_at
    end

    test "is single use", %{user: user, code: code} do
      assert {:ok, _user} = PhoneVerification.verify(user, code)
      assert PhoneVerification.verify(user, code) == {:error, :already_used}
    end

    test "rejects a wrong code and counts the attempt", %{user: user} do
      assert PhoneVerification.verify(user, "000000") == {:error, :invalid_code}
      assert Repo.get_by!(OtpChallenge, phone: user.phone).attempts == 1
    end

    test "stops and logs a brute-force loop after three attempts", %{user: user} do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          for _ <- 1..3, do: PhoneVerification.verify(user, "000000")
        end)

      assert log =~ "OTP lockout"
      assert PhoneVerification.verify(user, "000000") == {:error, :too_many_attempts}
      refute Accounts.get_user!(user.id).phone_verified_at
    end

    test "rejects an expired code", %{user: user, code: code} do
      Repo.update_all(OtpChallenge,
        set: [expires_at: DateTime.add(DateTime.utc_now(:second), -1, :second)]
      )

      assert PhoneVerification.verify(user, code) == {:error, :expired}
    end

    test "reports no challenge", %{user: user} do
      Repo.delete_all(OtpChallenge)
      assert PhoneVerification.verify(user, "123456") == {:error, :no_challenge}
    end
  end

  test "verify/2 before the code has been generated", %{user: user} do
    {:ok, :queued} = PhoneVerification.request(user)
    assert PhoneVerification.verify(user, "123456") == {:error, :no_code}
  end

  defp age_challenges do
    Repo.update_all(OtpChallenge,
      set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -61, :second)]
    )
  end

  defp exhaust(name, key) do
    {window, limit} = RateLimit.limit(name)

    for _ <- 1..limit do
      assert RateLimit.check(key, window, limit) == :ok
    end
  end
end
