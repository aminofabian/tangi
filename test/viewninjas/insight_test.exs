defmodule ViewNinjas.InsightTest do
  @moduledoc """
  First-party, PII-free page views (build-plan.md M6, scope.md §6, §13).
  """

  use ViewNinjas.DataCase, async: true

  import ExUnit.CaptureLog
  import ViewNinjas.AccountsFixtures

  alias ViewNinjas.Insight

  @at ~U[2026-09-30 10:00:00Z]

  describe "visitor_hash/3" do
    test "is stable within a day and different across days" do
      hash = Insight.visitor_hash("1.2.3.4", "UA", @at)

      assert Insight.visitor_hash("1.2.3.4", "UA", ~U[2026-09-30 23:59:59Z]) == hash
      refute Insight.visitor_hash("1.2.3.4", "UA", ~U[2026-10-01 00:00:01Z]) == hash
    end

    test "differs by address and by agent" do
      refute Insight.visitor_hash("1.2.3.4", "UA", @at) ==
               Insight.visitor_hash("5.6.7.8", "UA", @at)

      refute Insight.visitor_hash("1.2.3.4", "UA", @at) ==
               Insight.visitor_hash("1.2.3.4", "UB", @at)
    end

    test "is a hex digest that carries none of the raw input" do
      hash = Insight.visitor_hash("1.2.3.4", "UA", @at)

      assert hash =~ ~r/^[0-9a-f]{32}$/
      refute hash =~ "1.2.3.4"
    end
  end

  describe "device_class/1" do
    test "reads the common agents" do
      assert Insight.device_class("Mozilla/5.0 (Linux; Android 12) AppleWebKit Mobile") ==
               "mobile"

      assert Insight.device_class("Mozilla/5.0 (iPad; CPU OS 15_0) AppleWebKit") == "tablet"
      assert Insight.device_class("Mozilla/5.0 (Android 12; SM-T500) AppleWebKit") == "tablet"
      assert Insight.device_class("Mozilla/5.0 (Windows NT 10.0; Win64) Gecko") == "desktop"
      assert Insight.device_class(nil) == "other"
    end
  end

  describe "record_page_view/1" do
    test "stores the path, device class and hash, and no raw address" do
      user = user_fixture()

      assert :ok =
               Insight.record_page_view(%{
                 path: "/offers/7",
                 ip: "1.2.3.4",
                 user_agent: "Mozilla/5.0 (Linux; Android 12) AppleWebKit Mobile",
                 user_id: user.id,
                 referrer: "https://google.com/",
                 utm: %{"utm_source" => "wa"}
               })

      assert [view] = Insight.list_page_views()
      assert view.path == "/offers/7"
      assert view.device_class == "mobile"
      assert view.user_id == user.id
      assert view.referrer == "https://google.com/"
      assert view.utm_source == "wa"
      assert view.visitor_hash =~ ~r/^[0-9a-f]{32}$/
    end

    test "a signed-out view carries no user" do
      assert :ok = Insight.record_page_view(%{path: "/", ip: "1.2.3.4", user_agent: "UA"})

      assert [%{user_id: nil}] = Insight.list_page_views()
    end

    test "a broken view is logged, not raised" do
      log =
        capture_log(fn ->
          assert :ok = Insight.record_page_view(%{ip: "1.2.3.4"})
        end)

      assert log =~ "page view not recorded"
      assert Insight.list_page_views() == []
    end
  end
end
