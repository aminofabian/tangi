defmodule ViewNinjas.SmsTest do
  use ViewNinjas.DataCase, async: true

  import ExUnit.CaptureLog
  import ViewNinjas.AccountsFixtures

  alias ViewNinjas.Sms
  alias ViewNinjas.Sms.SmsMessage

  describe "send_message/1" do
    test "records the message and the provider's reference and cost" do
      assert {:ok, message} =
               Sms.send_message(%{to: unique_user_phone(), template: "test", body: "hello"})

      assert message.status == :sent
      assert message.provider == "test"
      assert message.provider_ref =~ "test-"
      assert message.cost_micros == 0
    end

    test "refuses and alerts when the daily cap is reached" do
      # A message that has already used up the day's budget.
      Repo.insert!(%SmsMessage{
        to: unique_user_phone(),
        template: "test",
        provider: "test",
        cost_micros: Sms.daily_cap_micros()
      })

      log =
        capture_log(fn ->
          assert Sms.send_message(%{to: unique_user_phone(), template: "test", body: "hi"}) ==
                   {:error, :spend_cap_reached}
        end)

      assert log =~ "SMS alert: daily_cap_reached"
    end

    test "counts messages whose cost is not known yet at the estimated cost" do
      estimate = Sms.estimated_cost_micros()
      count = div(Sms.daily_cap_micros(), estimate) + 1

      for _ <- 1..count do
        Repo.insert!(%SmsMessage{to: unique_user_phone(), template: "test", provider: "test"})
      end

      refute Sms.within_daily_cap?()
    end
  end

  describe "record_delivery/2" do
    test "updates the message matched by reference" do
      {:ok, message} = Sms.send_message(%{to: unique_user_phone(), template: "test", body: "x"})

      assert {:ok, updated} = Sms.record_delivery(message.provider_ref, :delivered)
      assert updated.status == :delivered
      assert Repo.get!(SmsMessage, message.id).status == :delivered
    end

    test "ignores an unknown reference" do
      assert Sms.record_delivery("does-not-exist", :delivered) == {:error, :not_found}
    end
  end
end
