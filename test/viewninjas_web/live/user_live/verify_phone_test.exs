defmodule ViewNinjasWeb.UserLive.VerifyPhoneTest do
  use ViewNinjasWeb.ConnCase, async: true

  use Oban.Testing, repo: ViewNinjas.Repo

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures

  alias ViewNinjas.Accounts
  alias ViewNinjas.Sms.Providers.Test, as: SmsOutbox
  alias ViewNinjas.Workers.DeliverOtp

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "a signed out visitor is sent to log in" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(build_conn(), ~p"/users/verify-phone")
  end

  test "shows the code field and a send button", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/users/verify-phone")

    assert html =~ "6-digit code"
    assert has_element?(lv, "#otp_form input[autocomplete='one-time-code']")
    assert has_element?(lv, "#resend-button", "Send code")
  end

  test "sends a code and verifies the phone", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/verify-phone")

    lv |> element("#resend-button") |> render_click()
    assert render(lv) =~ "We sent a code"

    [job] = all_enqueued(worker: DeliverOtp)
    :ok = perform_job(DeliverOtp, job.args)
    code = SmsOutbox.last_code(user.phone)
    assert code

    lv |> form("#otp_form", user: %{"code" => code}) |> render_submit()

    assert_redirect(lv, ~p"/account")
    assert Accounts.get_user!(user.id).phone_verified_at
  end

  test "shows a resend countdown and disables the button", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/verify-phone")

    lv |> element("#resend-button") |> render_click()

    assert render(lv) =~ "Resend in"
    assert has_element?(lv, "#resend-button[disabled]")
  end

  test "says plainly when the code is wrong", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/verify-phone")

    lv |> element("#resend-button") |> render_click()
    [job] = all_enqueued(worker: DeliverOtp)
    :ok = perform_job(DeliverOtp, job.args)

    html = lv |> form("#otp_form", user: %{"code" => "000000"}) |> render_submit()

    assert html =~ "not right"
  end

  test "a verified phone shows the done state" do
    user = verified_user_fixture()
    conn = log_in_user(build_conn(), user)

    {:ok, _lv, html} = live(conn, ~p"/users/verify-phone")

    assert html =~ "is verified"
  end
end
