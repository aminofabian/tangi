defmodule ViewNinjasWeb.PwaTest do
  @moduledoc """
  The PWA groundwork from scope.md §12 is a shipped part of M0, so assert the
  manifest and icons are actually served rather than trusting the file tree.
  """
  use ViewNinjasWeb.ConnCase, async: true

  test "serves the web app manifest", %{conn: conn} do
    conn = get(conn, ~p"/manifest.json")

    assert response(conn, 200) =~ "ViewNinjas"
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
    for path <- ~w(/images/logo.png /images/logo-mark.png) do
      conn = get(conn, path)

      assert response(conn, 200) =~ <<0x89, "PNG">>
    end
  end
end
