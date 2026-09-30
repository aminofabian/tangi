defmodule ViewNinjas.Suppliers.V2Test do
  # Mutates global supplier config (the Req test plug), so keep this serial.
  use ExUnit.Case, async: false

  alias ViewNinjas.Suppliers.{Supplier, V2}

  setup do
    previous = Application.get_env(:viewninjas, :suppliers, [])
    on_exit(fn -> Application.put_env(:viewninjas, :suppliers, previous) end)

    Application.put_env(
      :viewninjas,
      :suppliers,
      Keyword.put(previous, :req_options, plug: {Req.Test, __MODULE__})
    )

    supplier = %Supplier{
      slug: "panel",
      base_url: "https://panel.test/api/v2",
      api_key: "secret-key"
    }

    %{supplier: supplier}
  end

  test "services/1 posts the key and action and parses the whole pull", %{supplier: supplier} do
    Req.Test.stub(__MODULE__, fn conn ->
      assert Plug.Conn.get_req_header(conn, "content-type") == [
               "application/x-www-form-urlencoded"
             ]

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "key=secret-key"
      assert body =~ "action=services"

      Req.Test.json(conn, [
        %{
          "service" => 902,
          "name" => "IG followers - refill",
          "type" => "Default",
          "category" => "Instagram",
          "rate" => "1.20",
          "min" => "100",
          "max" => "50000",
          "refill" => true,
          "cancel" => false
        },
        %{
          "service" => 903,
          "name" => "IG likes",
          "type" => "Default",
          "category" => "Instagram",
          "rate" => "0.05",
          "min" => "50",
          "max" => "10000",
          "refill" => false,
          "cancel" => false
        }
      ])
    end)

    assert {:ok, [first, second]} = V2.services(supplier)
    assert first.external_id == "902"
    assert first.name == "IG followers - refill"
    assert first.rate_micros == 1_200_000
    assert first.min == 100
    assert first.max == 50_000
    assert first.refill == true
    assert second.rate_micros == 50_000
    assert second.refill == false
  end

  test "balance/1 parses the USD float into micros", %{supplier: supplier} do
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"balance" => "12.3456"}) end)

    assert V2.balance(supplier) == {:ok, 12_345_600}
  end

  test "a rejected key is one clear error", %{supplier: supplier} do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"error" => "Incorrect API key"})
    end)

    assert V2.balance(supplier) == {:error, {:api_error, "Incorrect API key"}}
  end

  test "a non-200 is an http error", %{supplier: supplier} do
    Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 403, "forbidden") end)

    assert {:error, {:http_error, 403, _body}} = V2.services(supplier)
  end

  test "an unreadable body is an invalid response", %{supplier: supplier} do
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"unexpected" => true}) end)

    assert V2.services(supplier) == {:error, {:invalid_response, %{"unexpected" => true}}}
  end

  describe "add/4" do
    test "posts the service, link and quantity and returns the panel's order id", %{
      supplier: supplier
    } do
      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body =~ "action=add"
        assert body =~ "service=902"
        assert body =~ "quantity=1000"
        assert body =~ "link=https%3A%2F%2Finstagram.com%2Fviewninjas"

        Req.Test.json(conn, %{"order" => 23_501})
      end)

      assert V2.add(supplier, "902", "https://instagram.com/viewninjas", 1000) == {:ok, "23501"}
    end

    test "a rejection is a definite api error", %{supplier: supplier} do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"error" => "Not enough funds"})
      end)

      assert V2.add(supplier, "902", "https://x.test", 1000) ==
               {:error, {:api_error, "Not enough funds"}}
    end

    test "a timeout is a transport error, not an answer", %{supplier: supplier} do
      Req.Test.stub(__MODULE__, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      assert {:error, {:transport, %Req.TransportError{reason: :timeout}}} =
               V2.add(supplier, "902", "https://x.test", 1000)
    end

    test "a body we cannot read is not an order id", %{supplier: supplier} do
      Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"queued" => true}) end)

      assert {:error, {:invalid_response, %{"queued" => true}}} =
               V2.add(supplier, "902", "https://x.test", 1000)
    end
  end

  describe "status/2" do
    test "reads one entry per order id, as panels key them", %{supplier: supplier} do
      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body =~ "action=status"
        assert body =~ "order=1%2C2"

        Req.Test.json(conn, %{
          "1" => %{
            "status" => "Completed",
            "start_count" => "100",
            "remains" => "0",
            "charge" => "1.08",
            "currency" => "USD"
          },
          "2" => %{"status" => "In progress", "start_count" => "50", "remains" => "500"}
        })
      end)

      assert {:ok, [first, second]} = V2.status(supplier, ["1", "2"])

      assert first == %{
               external_order_id: "1",
               status: "Completed",
               start_count: 100,
               remains: 0,
               charge_usd_micros: 1_080_000,
               currency: "USD"
             }

      assert second.external_order_id == "2"
      assert second.status == "In progress"
      assert second.charge_usd_micros == nil
    end

    test "also reads the nested shape some panels use", %{supplier: supplier} do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"orders" => %{"9" => %{"status" => "Pending"}}})
      end)

      assert {:ok, [%{external_order_id: "9", status: "Pending"}]} = V2.status(supplier, ["9"])
    end

    test "an error is an api error", %{supplier: supplier} do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"error" => "Incorrect order ID"})
      end)

      assert V2.status(supplier, ["1"]) == {:error, {:api_error, "Incorrect order ID"}}
    end
  end

  describe "refill/2 and refill_status/2" do
    test "refill/2 posts the order and returns the panel's refill id", %{supplier: supplier} do
      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body =~ "action=refill"
        assert body =~ "order=23501"
        Req.Test.json(conn, %{"refill" => 7654})
      end)

      assert V2.refill(supplier, "23501") == {:ok, "7654"}
    end

    test "refill/2 turns a rejection into an api error", %{supplier: supplier} do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"error" => "Refill not available"})
      end)

      assert V2.refill(supplier, "23501") == {:error, {:api_error, "Refill not available"}}
    end

    test "refill_status/2 reads the panel's word", %{supplier: supplier} do
      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body =~ "action=refill_status"
        assert body =~ "refill=7654"
        Req.Test.json(conn, %{"status" => "Completed"})
      end)

      assert V2.refill_status(supplier, "7654") == {:ok, "Completed"}
    end

    test "refill_status/2 rejects a body it cannot read", %{supplier: supplier} do
      Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"queued" => true}) end)

      assert V2.refill_status(supplier, "7654") ==
               {:error, {:invalid_response, %{"queued" => true}}}
    end
  end
end
