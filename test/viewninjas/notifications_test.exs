defmodule ViewNinjas.NotificationsTest do
  @moduledoc """
  Telling the customer (build-plan.md M11, scope.md §11): preferences, quiet
  hours, and the message an event produces.
  """

  use ViewNinjas.DataCase, async: true

  import ViewNinjas.AccountsFixtures
  import ViewNinjas.OrdersFixtures

  alias ViewNinjas.{Notifications, Orders, Payments}

  describe "preferences/1" do
    test "defaults to both channels on, any hour" do
      preferences = Notifications.preferences(verified_user_fixture())

      assert preferences.sms == %{opted_in: true, quiet_hours: nil}
      assert preferences.email == %{opted_in: true, quiet_hours: nil}
    end

    test "saves and reads back an opt-out and quiet hours" do
      user = verified_user_fixture()

      assert {:ok, :saved} =
               Notifications.save_preferences(user, %{
                 "sms_opted_in" => "false",
                 "sms_quiet_hours" => "21:00-07:00",
                 "email_opted_in" => "true"
               })

      assert Notifications.opted_in?(user, :sms) == false
      assert Notifications.quiet_hours(user, :sms) == "21:00-07:00"
      assert Notifications.suppressed?(user, :sms)
      refute Notifications.suppressed?(user, :email)
    end

    test "rejects a quiet-hours string that is not a window" do
      user = verified_user_fixture()

      assert {:error, changeset} =
               Notifications.save_preferences(user, %{
                 "sms_opted_in" => "true",
                 "sms_quiet_hours" => "evening"
               })

      assert changeset.errors[:quiet_hours]
    end
  end

  describe "quiet hours" do
    test "wraps midnight and honours the half-open window" do
      assert Notifications.in_quiet_hours?("21:00-07:00", ~T[22:30:00])
      assert Notifications.in_quiet_hours?("21:00-07:00", ~T[03:00:00])
      refute Notifications.in_quiet_hours?("21:00-07:00", ~T[07:00:00])
      refute Notifications.in_quiet_hours?("21:00-07:00", ~T[12:00:00])
    end

    test "handles a daytime window, a blank, and nonsense" do
      assert Notifications.in_quiet_hours?("09:00-17:00", ~T[10:00:00])
      refute Notifications.in_quiet_hours?("09:00-17:00", ~T[18:00:00])
      refute Notifications.in_quiet_hours?(nil, ~T[10:00:00])
      refute Notifications.in_quiet_hours?("12:00-12:00", ~T[12:00:00])
      refute Notifications.in_quiet_hours?("lunch", ~T[12:00:00])
    end

    test "snooze_seconds is a positive number of minutes" do
      user = verified_user_fixture()

      assert Notifications.snooze_seconds(user, :sms) == 60

      {:ok, :saved} =
        Notifications.save_preferences(user, %{
          "sms_opted_in" => "true",
          "sms_quiet_hours" => "21:00-07:00"
        })

      assert Notifications.snooze_seconds(user, :sms) >= 60
    end
  end

  describe "messages" do
    test "the paid SMS names the offer, the amount and the receipt" do
      order = paid_order_with_lane_fixture()
      payment = payment_fixture(%{order: order})
      {:ok, sent} = Payments.mark_pending(payment, "malipo-n")
      {:ok, _settled} = Payments.settle(sent, "QKH7XYZ123")

      loaded = Orders.get_order_with_lane(order.id)
      {template, body} = Notifications.sms(loaded, :paid)

      assert template == "order_paid"
      assert body =~ "we have your"
      assert body =~ "QKH7XYZ123"
      assert body =~ "KSh"
    end

    test "the refunded SMS names the money coming back" do
      order = paid_order_with_lane_fixture()
      {_template, body} = Notifications.sms(order, :refunded)

      assert body =~ "back in your wallet"
    end
  end
end
