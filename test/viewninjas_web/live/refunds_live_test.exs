defmodule ViewNinjasWeb.RefundsLiveTest do
  @moduledoc """
  The refund policy in the open (build-plan.md M12, scope.md §13, §17).
  """

  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.CatalogFixtures

  test "the policy is public, promises the credit and names the risk", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/refunds")

    assert has_element?(lv, "#refund-undelivered")
    assert has_element?(lv, "#refund-wallet")
    assert has_element?(lv, "#refund-honest")

    assert render(lv) =~ "Undelivered quantity comes back"
    assert render(lv) =~ "not affiliated with"
  end

  test "the offer page links to it", %{conn: conn} do
    offer = published_offer_fixture()

    {:ok, lv, _html} = live(conn, ~p"/offers/#{offer.id}")

    assert has_element?(lv, "#refund-link")
  end
end
