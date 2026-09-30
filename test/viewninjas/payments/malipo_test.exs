defmodule ViewNinjas.Payments.MalipoTest do
  @moduledoc """
  The Malipo Connect client (docs/malipo-connect.md §9): request shape, response
  parsing, and normalized errors.
  """

  # Mutates global client config (the Req test plug), so keep this serial. It
  # reads the settings store now, so it needs the sandbox.
  use ViewNinjas.DataCase, async: false

  alias ViewNinjas.Payments.Malipo

  @config ViewNinjas.Payments.Malipo

  setup do
    previous = Application.get_env(:viewninjas, @config, [])

    on_exit(fn -> Application.put_env(:viewninjas, @config, previous) end)

    Application.put_env(
      :viewninjas,
      @config,
      previous
      |> Keyword.put(:base_url, "https://malipo.test")
      |> Keyword.put(:secret_key, "sk_live_test")
      |> Keyword.put(:req_options, plug: {Req.Test, __MODULE__})
    )

    :ok
  end

  test "create/1 posts the amount, phone, key and reference" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer sk_live_test"]
      assert Plug.Conn.get_req_header(conn, "content-type") == ["application/json"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert Jason.decode!(body) == %{
               "amount" => "276.00",
               "customer_phone" => "254712345678",
               "idempotency_key" => "order-7-1",
               "reference" => "order-7"
             }

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{
          "id" => "pay_1",
          "status" => "pending",
          "amount" => "276.00",
          "currency" => "KES"
        })
      )
    end)

    assert {:ok, payment} =
             Malipo.create(%{
               amount: "276.00",
               customer_phone: "254712345678",
               idempotency_key: "order-7-1",
               reference: "order-7"
             })

    assert payment.id == "pay_1"
    assert payment.status == :pending
    assert payment.currency == "KES"
    assert payment.receipt == nil
  end

  test "get/1 reads a settled payment with its receipt" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"id" => "pay_1", "status" => "settled", "receipt" => "QKH7XYZ123"})
    end)

    assert {:ok, payment} = Malipo.get("pay_1")
    assert payment.status == :settled
    assert payment.receipt == "QKH7XYZ123"
  end

  test "get/1 reads a failure with its kind and message" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "id" => "pay_1",
        "status" => "failed",
        "failure_kind" => "wrong_pin",
        "failure_message" => "The PIN was wrong."
      })
    end)

    assert {:ok, payment} = Malipo.get("pay_1")
    assert payment.status == :failed
    assert payment.failure_kind == "wrong_pin"
  end

  test "a rejected key normalizes to one clear error" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        401,
        Jason.encode!(%{"error" => "unauthorized", "message" => "nope"})
      )
    end)

    assert Malipo.get("pay_1") == {:error, {:malipo, "unauthorized", "nope", 401}}
    assert Malipo.error_message({:malipo, "unauthorized", "nope", 401}) =~ "key was rejected"
  end

  test "a destination that is not confirmed is its own error" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        409,
        Jason.encode!(%{"error" => "destination_inactive", "message" => "confirm a till"})
      )
    end)

    assert {:error, {:malipo, "destination_inactive", _message, 409}} =
             Malipo.create(%{
               amount: "1.00",
               customer_phone: "254700000000",
               idempotency_key: "order-1-1"
             })

    assert Malipo.error_message({:malipo, "destination_inactive", "x", 409}) =~ "destination"
  end

  test "a 5xx is an http error, not a rail error" do
    Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 502, "bad gateway") end)

    assert Malipo.get("pay_1") == {:error, {:http_error, 502}}
  end

  test "a body we cannot read is an invalid response" do
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"status" => "weird"}) end)

    assert {:error, {:invalid_response, _raw}} = Malipo.get("pay_1")
  end

  test "a transport error is a transport error" do
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.transport_error(conn, :timeout) end)

    assert {:error, {:transport, _reason}} = Malipo.get("pay_1")
    assert Malipo.error_message({:transport, :timeout}) =~ "Could not reach"
  end

  test "the secret key is the bearer and create uses the configured path" do
    Application.put_env(:viewninjas, @config,
      base_url: "https://backend.kioskpay.co.ke",
      secret_key: "sk_live_test",
      client_id: "pk_live_test",
      create_path: "/v1/payments",
      check_path: "/v1/payments/{id}",
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.host == "backend.kioskpay.co.ke"
      assert conn.request_path == "/v1/payments"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer sk_live_test"]

      Req.Test.json(conn, %{"id" => "pay_9", "status" => "pending"})
    end)

    assert {:ok, payment} =
             Malipo.create(%{
               amount: "1.00",
               customer_phone: "254700000000",
               idempotency_key: "order-9-1"
             })

    assert payment.id == "pay_9"
  end

  test "a client id is not sent" do
    Application.put_env(:viewninjas, @config,
      base_url: "https://backend.kioskpay.co.ke",
      secret_key: nil,
      client_id: "pk_live_test",
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    Req.Test.stub(__MODULE__, fn conn ->
      flunk("a client id must not leave the app: #{conn.method} #{conn.request_path}")
    end)

    assert Malipo.create(%{
             amount: "1.00",
             customer_phone: "254700000000",
             idempotency_key: "order-9-1"
           }) == {:error, :client_id}

    assert Malipo.error_message(:client_id) =~ "sk_live_"
    refute Malipo.ready?()
  end

  test "a client id saved in the secret field is not sent" do
    Application.put_env(:viewninjas, @config,
      secret_key: "  Bearer pk_live_test  ",
      client_id: nil,
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    assert Malipo.get("pay_1") == {:error, :client_id}
  end

  test "check replaces {id} on the configured path" do
    Application.put_env(:viewninjas, @config,
      base_url: "https://backend.kioskpay.co.ke",
      secret_key: "sk_live_test",
      client_id: "pk_live_test",
      check_path: "/v1/payments/{id}",
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/v1/payments/pay_9"
      Req.Test.json(conn, %{"id" => "pay_9", "status" => "settled", "receipt" => "QKH1"})
    end)

    assert {:ok, %{status: :settled}} = Malipo.get("pay_9")
  end

  test "with no key configured it refuses instead of prompting" do
    Application.put_env(:viewninjas, @config, base_url: "https://malipo.test", secret_key: nil)

    assert Malipo.get("pay_1") == {:error, :not_configured}
    assert Malipo.error_message(:not_configured) =~ "not configured"
  end

  test "the default error message is safe for a customer" do
    assert Malipo.error_message({:something, :odd}) =~ "unavailable"
  end
end
