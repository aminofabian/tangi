defmodule ViewNinjasWeb.Admin.SettingsLiveTest do
  @moduledoc """
  The super-admin settings screen (build-plan.md M12, scope.md §7, §11).
  """

  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import ViewNinjas.AccountsFixtures

  alias ViewNinjas.Settings

  setup do
    # Swoosh's API client is disabled in the test environment, so Resend is never
    # actually reachable here. The test-email cases turn it on with a base URL
    # that refuses connections, which exercises the real send path (and its error
    # reporting) without ever talking to Resend.
    previous_client = Application.get_env(:swoosh, :api_client)
    previous_resend = Application.get_env(:viewninjas, :resend)

    on_exit(fn ->
      Application.put_env(:swoosh, :api_client, previous_client)
      Application.put_env(:viewninjas, :resend, previous_resend)
    end)

    :ok
  end

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

  test "a super-admin can set and clear the Resend key", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/settings")

    assert has_element?(lv, "#settings-Mail")
    assert has_element?(lv, "#setting-resend_api_key")
    assert has_element?(lv, "#setting-resend_base_url")
    assert has_element?(lv, "#setting-mailer_from")

    lv
    |> form("#settings-form", settings: %{"resend_api_key" => "re_from_the_back_office"})
    |> render_submit()

    assert Settings.resend_api_key() == "re_from_the_back_office"
    assert Settings.email_configured?()

    # A secret is never echoed back into the page.
    refute render(lv) =~ "re_from_the_back_office"

    lv |> element("#clear-resend_api_key") |> render_click()

    refute Settings.stored_settings()["resend_api_key"]
    refute Settings.email_configured?()
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

  describe "the test email button" do
    test "is offered, and disabled while email cannot be sent", %{conn: conn} do
      conn = log_in_user(conn, super_admin_fixture())

      {:ok, lv, _html} = live(conn, ~p"/admin/settings")

      assert has_element?(lv, "#settings-test-email")
      assert has_element?(lv, "#send-test-email[disabled]")
      assert has_element?(lv, "#test-email-not-configured")
    end

    test "becomes available once a key is saved", %{conn: conn} do
      conn = log_in_user(conn, super_admin_fixture())

      # A saved key alone is not enough — the HTTP client has to be there too.
      {:ok, lv, _html} = live(conn, ~p"/admin/settings")

      lv
      |> form("#settings-form", settings: %{"resend_api_key" => "re_a_key"})
      |> render_submit()

      assert has_element?(lv, "#send-test-email[disabled]")

      Application.put_env(:swoosh, :api_client, Swoosh.ApiClient.Req)

      {:ok, lv, _html} = live(conn, ~p"/admin/settings")

      refute has_element?(lv, "#send-test-email[disabled]")
      refute has_element?(lv, "#test-email-not-configured")
    end

    test "reports what Resend said when the send fails", %{conn: conn} do
      admin = super_admin_fixture()
      conn = log_in_user(conn, admin)

      {:ok, _} = Settings.put("resend_api_key", "re_a_key", nil)
      Application.put_env(:swoosh, :api_client, Swoosh.ApiClient.Req)
      # Port 1 refuses instantly, so the failure is the real send path reporting a
      # real transport error — no network, no waiting, no key sent anywhere.
      {:ok, _} = Settings.put("resend_base_url", "http://127.0.0.1:1", nil)

      {:ok, lv, _html} = live(conn, ~p"/admin/settings")

      html = lv |> element("#send-test-email") |> render_click()

      assert html =~ "Resend did not send it"
      refute_email_sent()
    end

    test "addresses the message to the address it is handed", %{conn: conn} do
      admin = super_admin_fixture()
      conn = log_in_user(conn, admin)

      {:ok, lv, _html} = live(conn, ~p"/admin/settings")

      # The button takes its recipient from the session, never from the browser,
      # so the only address it can ever reach is the signed-in super-admin's.
      message = ViewNinjas.Email.test_message(admin.email)

      assert message.to == [{"", admin.email}]
      assert message.subject =~ "test email"
      assert has_element?(lv, "#send-test-email")
    end
  end
end
