defmodule ViewNinjas.Workers.AirtimeWorkersTest do
  @moduledoc """
  The airtime send, confirm and sweep (docs/instalipa-airtime.md §12): one send,
  delivered only on a confirming Success, and a person for anything ambiguous.
  """

  # Mutates global client config (the Req test plug), so keep this serial.
  use ViewNinjas.DataCase, async: false
  use Oban.Testing, repo: ViewNinjas.Repo

  import ViewNinjas.AirtimeFixtures

  alias ViewNinjas.Airtime
  alias ViewNinjas.Airtime.Instalipa.Token
  alias ViewNinjas.Wallet
  alias ViewNinjas.Workers.{ConfirmAirtime, SendAirtime, SweepPendingAirtime}

  @config ViewNinjas.Airtime.Instalipa

  setup do
    previous = Application.get_env(:viewninjas, @config, [])

    on_exit(fn -> Application.put_env(:viewninjas, @config, previous) end)

    Application.put_env(:viewninjas, @config,
      base_url: "https://instalipa.test",
      token_path: "/api/v1/token",
      airtime_path: "/api/v1/airtime",
      status_path: "/api/v1/status/{id}",
      consumer_key: "ck_test",
      consumer_secret: "cs_test",
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    Token.reset()
    :ok
  end

  # The token endpoint is always answered; `handler` answers everything else.
  defp install_stub(handler) do
    Req.Test.stub(__MODULE__, fn conn ->
      case conn.request_path do
        "/api/v1/token" ->
          json(conn, 200, %{"access_token" => "tok_1", "expires_in" => 3600})

        path ->
          handler.(conn, path)
      end
    end)
  end

  defp json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  # A submitted order built directly, so no send job or HTTP is involved.
  defp submitted_order!(attrs \\ %{}) do
    order = airtime_order_fixture(attrs)
    {:ok, sending} = Airtime.mark_sending(order)

    {:ok, submitted} =
      Airtime.mark_submitted(sending, %{
        id: "INSTAid_#{System.unique_integer([:positive])}",
        status: :submitted
      })

    submitted
  end

  defp backdate(order, seconds) do
    ViewNinjas.Repo.update_all(
      from(o in ViewNinjas.Airtime.AirtimeOrder, where: o.id == ^order.id),
      set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -seconds)]
    )
  end

  describe "SendAirtime" do
    test "a paid order is sent once and waits on the rail" do
      order = airtime_order_fixture()

      install_stub(fn conn, "/api/v1/airtime" ->
        assert conn.method == "POST"

        assert Plug.Conn.get_req_header(conn, "idempotency-key") == [order.idempotency_key]

        json(conn, 200, %{
          "transaction_id" => "INSTAid_1",
          "status" => "Submitted",
          "details" => "Pending",
          "discount" => "0.60",
          "balance" => "470.00"
        })
      end)

      assert :ok = perform_job(SendAirtime, %{"airtime_order_id" => order.id})

      sent = Airtime.get_order(order.id)
      assert sent.state == :submitted
      assert sent.instalipa_id == "INSTAid_1"
      assert sent.discount_cents == 60
      assert sent.float_cents == 47_000
      assert_enqueued(worker: ConfirmAirtime, args: %{"airtime_order_id" => order.id})
    end

    test "a duplicate is parked for a person, never resent" do
      order = airtime_order_fixture()

      install_stub(fn conn, "/api/v1/airtime" ->
        json(conn, 200, %{"status" => "Failed", "details" => "Duplicate request"})
      end)

      assert :ok = perform_job(SendAirtime, %{"airtime_order_id" => order.id})
      assert Airtime.get_order(order.id).state == :needs_review
    end

    test "a definite rejection fails the order and refunds the wallet" do
      user = funded_user(50_000)
      order = airtime_order_fixture(%{user: user})

      install_stub(fn conn, "/api/v1/airtime" ->
        json(conn, 402, %{"error" => "insufficient_float", "message" => "Float is empty"})
      end)

      assert :ok = perform_job(SendAirtime, %{"airtime_order_id" => order.id})

      refunded = Airtime.get_order(order.id)
      assert refunded.state == :refunded
      assert refunded.failure_kind == "insufficient_float"
      assert Wallet.balance(user) == 50_000
    end

    test "a transport error is parked, not failed" do
      order = airtime_order_fixture()

      install_stub(fn conn, "/api/v1/airtime" -> Req.Test.transport_error(conn, :timeout) end)

      assert :ok = perform_job(SendAirtime, %{"airtime_order_id" => order.id})
      assert Airtime.get_order(order.id).state == :needs_review
    end

    test "only a paid order is sent" do
      order = submitted_order!()
      install_stub(fn _conn, path -> flunk("unexpected request to #{path}") end)

      assert :ok = perform_job(SendAirtime, %{"airtime_order_id" => order.id})
      assert Airtime.get_order(order.id).state == :submitted
    end
  end

  describe "ConfirmAirtime" do
    test "a confirming Success delivers the order" do
      order = submitted_order!()
      id = order.instalipa_id

      install_stub(fn conn, "/api/v1/status/" <> ^id ->
        assert conn.method == "GET"
        json(conn, 200, %{"transaction_id" => id, "status" => "Success", "receipt" => "R251"})
      end)

      assert {:ok, delivered} = perform_job(ConfirmAirtime, %{"airtime_order_id" => order.id})
      assert delivered.state == :delivered
      assert delivered.receipt == "R251"
    end

    test "a confirming Failed refunds the wallet" do
      user = funded_user(50_000)
      order = submitted_order!(%{user: user})
      id = order.instalipa_id

      install_stub(fn conn, "/api/v1/status/" <> ^id ->
        json(conn, 200, %{
          "transaction_id" => id,
          "status" => "Failed",
          "details" => "Number barred"
        })
      end)

      assert :ok = perform_job(ConfirmAirtime, %{"airtime_order_id" => order.id})

      refunded = Airtime.get_order(order.id)
      assert refunded.state == :refunded
      assert Wallet.balance(user) == 50_000
    end

    test "a still-pending status snoozes" do
      order = submitted_order!()
      id = order.instalipa_id

      install_stub(fn conn, "/api/v1/status/" <> ^id ->
        json(conn, 200, %{"transaction_id" => id, "status" => "Pending"})
      end)

      assert {:snooze, _seconds} =
               perform_job(ConfirmAirtime, %{
                 "airtime_order_id" => order.id,
                 "deadline" => System.system_time(:second) + 60
               })

      assert Airtime.get_order(order.id).state == :submitted
    end
  end

  describe "SweepPendingAirtime" do
    test "re-enqueues a stale send and parks an abandoned one" do
      stale = submitted_order!()
      abandoned = submitted_order!()
      backdate(stale, 120)
      backdate(abandoned, 7_200)

      assert :ok = perform_job(SweepPendingAirtime, %{})

      assert_enqueued(worker: ConfirmAirtime, args: %{"airtime_order_id" => stale.id})
      assert Airtime.get_order(stale.id).state == :submitted
      assert Airtime.get_order(abandoned.id).state == :needs_review
    end
  end
end
