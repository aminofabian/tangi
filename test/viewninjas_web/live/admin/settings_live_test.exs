defmodule ViewNinjasWeb.Admin.SettingsLiveTest do
  @moduledoc """
  The super-admin settings screen (build-plan.md M12, scope.md §7, §11).
  """

  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures

  alias ViewNinjas.Settings

  test "a signed out visitor is sent to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/settings")
  end

  test "an ordinary admin is bounced", %{conn: conn} do
    conn = log_in_user(conn, admin_fixture())

    assert {:error, {:redirect, %{to: "/", flash: _}}} = live(conn, ~p"/admin/settings")
  end

  test "a super-admin sees the groups", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/settings")

    assert has_element?(lv, "#settings-form")
    assert has_element?(lv, "#settings-SMS")
    assert has_element?(lv, "#settings-Payments")
    assert has_element?(lv, "#setting-malipo_client_id")
    assert has_element?(lv, "#setting-malipo_base_url")
    assert has_element?(lv, "#setting-malipo_create_path")
    assert has_element?(lv, "#setting-malipo_check_path")
    assert has_element?(lv, "#setting-malipo_secret_key")
    assert render(lv) =~ "https://backend.kioskpay.co.ke"
    assert render(lv) =~ "/v1/payments/{id}"
    assert has_element?(lv, "#settings-bootstrap")
    assert has_element?(lv, "#admin-nav-settings")
  end

  test "saving a secret stores it and never echoes it back", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/settings")

    lv
    |> form("#settings-form", settings: %{"malipo_secret_key" => "sk_live_secret"})
    |> render_submit()

    assert Settings.malipo_secret_key() == "sk_live_secret"
    refute render(lv) =~ "sk_live_secret"
  end

  test "a non-secret is shown back and can be cleared", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/settings")

    lv
    |> form("#settings-form", settings: %{"malipo_base_url" => "https://malipo.example"})
    |> render_submit()

    assert Settings.malipo_base_url() == "https://malipo.example"
    assert render(lv) =~ "https://malipo.example"

    lv |> element("#clear-malipo_base_url") |> render_click()

    refute Settings.stored_settings()["malipo_base_url"]
  end

  test "a bad integer is refused with a message", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/settings")

    html =
      lv
      |> form("#settings-form", settings: %{"sms_daily_cap_micros" => "a lot"})
      |> render_submit()

    assert html =~ "whole number"
    refute Settings.stored_settings()["sms_daily_cap_micros"]
  end
end
