defmodule ViewNinjasWeb.AccountLiveTest do
  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures

  alias ViewNinjas.Accounts.Phone
  alias ViewNinjas.Notifications

  test "signed out: offers register and log in, Account tab active", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/account")

    assert has_element?(lv, "a[href='/users/register']")
    assert has_element?(lv, "a[href='/users/log-in']")
    assert has_element?(lv, "nav.vn-tabbar a[aria-current='page'][href='/account']")
  end

  test "signed in: shows the identity and the way out", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/account")

    assert has_element?(lv, "dd", user.email)
    assert has_element?(lv, "dd", Phone.format(user.phone))
    assert has_element?(lv, "a[href='/users/settings']")
    assert has_element?(lv, "a[href='/users/log-out']")
  end

  test "signed in and unverified: offers to verify the phone", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())

    {:ok, lv, _html} = live(conn, ~p"/account")

    assert has_element?(lv, "a[href='/users/verify-phone']")
  end

  test "signed in and verified: shows the verified badge", %{conn: conn} do
    conn = log_in_user(conn, verified_user_fixture())

    {:ok, lv, _html} = live(conn, ~p"/account")

    assert has_element?(lv, "span.vn-badge--ok", "Verified")
  end

  test "signed in: saves notification choices", %{conn: conn} do
    user = verified_user_fixture()
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/account")
    assert has_element?(lv, "#notifications-form")

    lv
    |> form("#notifications-form",
      notifications: %{
        sms_opted_in: "false",
        sms_quiet_hours: "21:00-07:00",
        email_opted_in: "true"
      }
    )
    |> render_submit()

    assert Notifications.opted_in?(user, :sms) == false
    assert Notifications.quiet_hours(user, :sms) == "21:00-07:00"
  end
end
