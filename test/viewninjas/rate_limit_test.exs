defmodule ViewNinjas.RateLimitTest do
  # This file tightens the limits for the duration of its assertions. That is
  # safe even while other modules run: every other test acts at most a couple
  # of times on any one key, so even the tight limits below allow them.
  use ExUnit.Case, async: false

  alias ViewNinjas.RateLimit

  setup do
    previous = Application.get_env(:viewninjas, :rate_limits)

    Application.put_env(:viewninjas, :rate_limits, %{
      signup_phone: {60_000, 2},
      login_identifier: {60_000, 2}
    })

    on_exit(fn -> Application.put_env(:viewninjas, :rate_limits, previous) end)
  end

  test "check/3 allows up to the limit, then denies" do
    key = unique_key()

    assert RateLimit.check(key, 60_000, 3) == :ok
    assert RateLimit.check(key, 60_000, 3) == :ok
    assert RateLimit.check(key, 60_000, 3) == :ok
    assert RateLimit.check(key, 60_000, 3) == {:error, :rate_limited}
  end

  test "sign-up is budgeted per phone" do
    phone = unique_key()
    ip = unique_key()

    assert RateLimit.allow_signup?(ip, phone)
    assert RateLimit.allow_signup?(ip, phone)
    refute RateLimit.allow_signup?(ip, phone)
  end

  test "login is budgeted per identifier" do
    identifier = unique_key()

    assert RateLimit.allow_login?(unique_key(), identifier)
    assert RateLimit.allow_login?(unique_key(), identifier)
    refute RateLimit.allow_login?(unique_key(), identifier)
  end

  test "switching it off makes it a no-op" do
    Application.put_env(:viewninjas, :rate_limiting, false)
    on_exit(fn -> Application.put_env(:viewninjas, :rate_limiting, true) end)

    key = unique_key()

    for _ <- 1..100 do
      assert RateLimit.check(key, 60_000, 1) == :ok
    end
  end

  test "every limit resolves, and an unknown one is loud" do
    assert {_window, _limit} = RateLimit.limit(:payment_user)
    assert {_window, _limit} = RateLimit.limit(:payment_phone)
    assert {_window, _limit} = RateLimit.limit(:otp_phone)

    assert_raise ArgumentError, fn -> RateLimit.limit(:not_a_limit) end
  end

  defp unique_key, do: "test:#{System.unique_integer([:positive])}"
end
