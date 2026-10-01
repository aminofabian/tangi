defmodule ViewNinjasWeb.PwaTest do
  @moduledoc """
  The PWA groundwork from scope.md §12 is a shipped part of M0, so assert the
  manifest and icons are actually served rather than trusting the file tree.
  """
  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures

  test "serves the web app manifest", %{conn: conn} do
    body = conn |> get(~p"/manifest.json") |> response(200)

    assert body =~ "Tangi"
    assert body =~ ~s("display": "standalone")
    assert body =~ ~s("start_url": "/")
  end

  test "serves the service worker that falls back to the offline splash", %{conn: conn} do
    conn = get(conn, ~p"/service-worker.js")

    assert [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "javascript"
    assert response(conn, 200) =~ "/offline.html"
  end

  test "serves the offline splash", %{conn: conn} do
    html = conn |> get(~p"/offline.html") |> response(200)

    assert html =~ "You're offline"
  end

  test "serves the icons referenced by the manifest", %{conn: conn} do
    for path <- ~w(/images/icon-192.png /images/icon-512.png
                   /images/maskable-192.png /images/maskable-512.png
                   /images/apple-touch-icon.png) do
      conn = get(conn, path)

      assert response(conn, 200) =~ <<0x89, "PNG">>
    end
  end

  test "serves the self-hosted brand webfonts", %{conn: conn} do
    for path <- ~w(/fonts/fredoka-latin.woff2 /fonts/nunito-latin.woff2) do
      conn = get(conn, path)

      assert response(conn, 200) =~ "wOF2"
    end
  end

  test "serves the brand artwork", %{conn: conn} do
    for path <- ~w(/images/logo.png /images/logo-mark.png /images/og-image.png) do
      conn = get(conn, path)

      assert response(conn, 200) =~ <<0x89, "PNG">>
    end
  end

  test "the shell's install nudge is wired to the bundled hook", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/shop")

    # A colocated hook is namespaced by the module that defines it, and that
    # namespaced name is the key the bundled JS registers. Asserting the rendered
    # attribute here keeps the two from drifting apart silently.
    assert has_element?(lv, "#pwa-install[phx-hook='ViewNinjasWeb.Layouts.PwaInstall']")
    assert has_element?(lv, "#pwa-install[phx-update='ignore']")
    # The one-click button and the dismiss control the hook binds to.
    assert has_element?(lv, "#pwa-install [data-pwa-install]")
    assert has_element?(lv, "#pwa-install [data-pwa-dismiss]")
    # It starts hidden; the hook reveals it once the browser offers install.
    assert has_element?(lv, "#pwa-install[hidden]")
  end

  test "the back office has no install nudge", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin")

    refute has_element?(lv, "#pwa-install")
  end

  test "the Account tab carries its own one-click install", %{conn: conn} do
    conn = log_in_user(conn, verified_user_fixture())

    {:ok, lv, _html} = live(conn, ~p"/account")

    assert has_element?(lv, "#install-card[phx-hook='ViewNinjasWeb.AccountLive.InstallApp']")
    assert has_element?(lv, "#install-card[hidden]")
    assert has_element?(lv, "#install-card [data-pwa-install]")
    # The manual steps iOS is shown, in place of a prompt it never gets.
    assert has_element?(lv, "#install-card [data-pwa-steps]")
    # The nudge defers to this card rather than saying the same thing twice.
    assert has_element?(lv, "#install-card[data-pwa-install-card]")
  end
end
