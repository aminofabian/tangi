defmodule ViewNinjasWeb.Admin.PricingLiveTest do
  @moduledoc """
  The money knobs screen (build-plan.md M5): super-admin only, append-only, and
  the FX series it records.
  """

  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures

  alias ViewNinjas.Pricing

  test "a signed out visitor is sent to log in" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/admin/pricing")
  end

  test "a signed in customer is bounced to the shop", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/pricing")
  end

  test "an ordinary admin cannot touch the margin", %{conn: conn} do
    conn = log_in_user(conn, admin_fixture())

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/pricing")
  end

  test "a super-admin sees the defaults in force", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/pricing")

    assert has_element?(lv, "#in-force")
    assert render(lv) =~ "130.00%"
    assert render(lv) =~ "129.4"
  end

  test "raising the margin appends a version", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/pricing")

    html =
      lv
      |> form("#settings-form", settings: %{margin_percent: "150", buffer_percent: "4"})
      |> render_submit()

    version = Pricing.current_settings()
    assert version.margin_bps == 15_000
    assert version.buffer_bps == 400
    assert html =~ "150.00%"
    assert has_element?(lv, "#version-#{version.id}")
  end

  test "recording a manual rate appends an FX row", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/pricing")

    lv
    |> form("#fx-form", fx: %{rate: "131.25"})
    |> render_submit()

    rate = Pricing.current_fx()
    assert rate.rate_ppm == 131_250_000
    assert rate.source == "manual"
    assert has_element?(lv, "#fx-#{rate.id}")
  end

  test "a bad margin is refused with a sentence, not a crash", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/pricing")

    lv
    |> form("#settings-form", settings: %{margin_percent: "nope", buffer_percent: "4"})
    |> render_submit()

    assert render(lv) =~ "Enter a number."
    assert Pricing.current_settings() == nil
  end
end
