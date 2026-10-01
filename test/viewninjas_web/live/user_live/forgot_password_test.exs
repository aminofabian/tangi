defmodule ViewNinjasWeb.UserLive.ForgotPasswordTest do
  @moduledoc """
  The password-reset request screen (scope.md §6: email is the recovery path).

  The screen must be indistinguishable for an address that has an account and one
  that does not, so the "no such user" case is asserted as carefully as the happy
  path — that uniformity is the security property, not a detail.
  """

  # The rate-limiting case turns limiting on, which is global application env —
  # and every test in this file shares one client IP, so an exhausted budget
  # would leak into the cases that assert on wording. Keep it serial, as
  # `settings_test.exs` does for the same reason.
  use ViewNinjasWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  import ViewNinjas.AccountsFixtures

  alias ViewNinjas.Accounts

  @generic "If your email is in our system, you will receive instructions"

  describe "the request screen" do
    test "renders the form", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/reset-password")

      assert html =~ "Forgot your password?"
      assert has_element?(_lv, "#reset_password_form")
      assert has_element?(_lv, "#reset_password_form input[type=email]")
    end

    test "sends a reset link to a known address", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      lv
      |> form("#reset_password_form", user: %{"email" => user.email})
      |> render_submit()

      assert render(lv) =~ @generic

      assert_email_sent(fn email ->
        assert email.to == [{"", user.email}]
        assert email.subject =~ "Reset password"
        assert email.text_body =~ "/users/reset-password/"
      end)
    end

    test "says the same thing for an address with no account", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      lv
      |> form("#reset_password_form", user: %{"email" => "nobody@nowhere.test"})
      |> render_submit()

      # Identical wording: the screen cannot be used to find out who has an account.
      assert render(lv) =~ @generic
      refute_email_sent()
    end

    test "the link it sends actually resolves to that user", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      lv
      |> form("#reset_password_form", user: %{"email" => user.email})
      |> render_submit()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      assert Accounts.get_user_by_reset_password_token(token).id == user.id
    end
  end

  describe "rate limiting" do
    test "stops a flood of reset requests from one IP" do
      original = Application.get_env(:viewninjas, :rate_limiting, true)
      Application.put_env(:viewninjas, :rate_limiting, true)
      on_exit(fn -> Application.put_env(:viewninjas, :rate_limiting, original) end)

      user = user_fixture()

      # Its own forwarded address, so exhausting this budget cannot silence the
      # wording assertions in the cases above.
      conn =
        build_conn()
        |> put_req_header("x-forwarded-for", "203.0.113.#{:rand.uniform(250)}")

      results =
        for _attempt <- 1..6 do
          {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

          lv
          |> form("#reset_password_form", user: %{"email" => user.email})
          |> render_submit()
        end

      # The limit is 5 per hour, so the sixth attempt is refused.
      assert Enum.any?(results, &(&1 =~ "Too many requests"))
    end
  end
end
