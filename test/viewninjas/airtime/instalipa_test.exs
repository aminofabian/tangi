defmodule ViewNinjas.Airtime.InstalipaTest do
  @moduledoc """
  The Instalipa airtime client (docs/instalipa-airtime.md §3–§4): the token it mints
  and caches, the send, the status, and the normalized errors.
  """

  # Mutates global client config (the Req test plug), so keep this serial. It reads
  # the settings store now, so it needs the sandbox.
  use ViewNinjas.DataCase, async: false

  alias ViewNinjas.Airtime.Instalipa
  alias ViewNinjas.Airtime.Instalipa.Token

  @config ViewNinjas.Airtime.Instalipa
  @token Jason.encode!(%{
           "access_token" => "tok_1",
           "token_type" => "Bearer",
           "expires_in" => 3600.0
         })

  setup do
    previous = Application.get_env(:viewninjas, @config, [])

    on_exit(fn -> Application.put_env(:viewninjas, @config, previous) end)

    Application.put_env(
      :viewninjas,
      @config,
      base_url: "https://instalipa.test",
      token_path: "/api/v1/token",
      airtime_path: "/api/v1/airtime",
      status_path: "/api/v1/status/{id}",
      consumer_key: "ck_test",
      consumer_secret: "cs_test",
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    # The cache is a process that outlives the test; start each one cold.
    Token.reset()
    :ok
  end

  # The token endpoint is always the same; `handler` answers everything else.
  defp install_stub(handler) do
    Req.Test.stub(__MODULE__, fn conn ->
      case conn.request_path do
        "/api/v1/token" ->
          assert conn.method == "POST"

          assert Plug.Conn.get_req_header(conn, "authorization") ==
                   ["Basic " <> Base.encode64("ck_test:cs_test")]

          send(self(), :token_minted)
          respond(conn, 200, @token)

        path ->
          handler.(conn, path)
      end
    end)
  end

  defp respond(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, body)
  end

  defp json(map), do: Jason.encode!(map)

  test "mints a token with HTTP Basic once, then serves it from the cache" do
    install_stub(fn _conn, path -> flunk("unexpected request to #{path}") end)

    assert {:ok, "tok_1"} = Token.fetch()
    assert {:ok, "tok_1"} = Token.fetch()

    assert_received :token_minted
    refute_received :token_minted
  end

  test "send_airtime/1 posts the number, amount, reference and idempotency key" do
    install_stub(fn conn, "/api/v1/airtime" ->
      assert conn.method == "POST"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer tok_1"]
      assert Plug.Conn.get_req_header(conn, "idempotency-key") == ["airtime-7-1"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert Jason.decode!(body) == %{
               "phone_number" => "254705340183",
               "amount" => "100",
               "reference" => "airtime-7"
             }

      respond(
        conn,
        200,
        json(%{
          "transaction_id" => "INSTAid_1",
          "status" => "Submitted",
          "details" => "Pending",
          "phone_number" => "254705340183",
          "amount" => "100",
          "discount" => "6.00",
          "balance" => "470.00",
          "reference" => "airtime-7",
          "receipt" => ""
        })
      )
    end)

    assert {:ok, tx} =
             Instalipa.send_airtime(%{
               phone: "254705340183",
               amount: "100",
               reference: "airtime-7",
               idempotency_key: "airtime-7-1"
             })

    assert tx.id == "INSTAid_1"
    assert tx.status == :submitted
    assert tx.discount == "6.00"
    assert tx.balance == "470.00"
  end

  test "a duplicate response is its own error, not a failed top-up" do
    install_stub(fn conn, "/api/v1/airtime" ->
      respond(conn, 200, json(%{"status" => "Failed", "details" => "Duplicate request"}))
    end)

    assert {:error, :duplicate} =
             Instalipa.send_airtime(%{phone: "254705340183", amount: "100"})

    assert Instalipa.error_message(:duplicate) =~ "duplicate"
  end

  test "status/1 reads the final state by transaction id" do
    install_stub(fn conn, "/api/v1/status/INSTAid_1" ->
      assert conn.method == "GET"

      respond(
        conn,
        200,
        json(%{"transaction_id" => "INSTAid_1", "status" => "Success", "receipt" => "R251"})
      )
    end)

    assert {:ok, tx} = Instalipa.status("INSTAid_1")
    assert tx.status == :success
    assert tx.receipt == "R251"
  end

  test "a 401 mints a fresh token and retries exactly once" do
    install_stub(fn conn, "/api/v1/airtime" ->
      attempt = Process.get(:airtime_attempt, 0) + 1
      Process.put(:airtime_attempt, attempt)

      if attempt == 1 do
        respond(conn, 401, json(%{"message" => "token expired"}))
      else
        respond(
          conn,
          200,
          json(%{"transaction_id" => "INSTAid_9", "status" => "Success", "receipt" => "R9"})
        )
      end
    end)

    assert {:ok, tx} = Instalipa.send_airtime(%{phone: "254705340183", amount: "100"})
    assert tx.status == :success
    assert Process.get(:airtime_attempt) == 2
    # One token for the first call, a second because the 401 forced a refresh.
    assert_received :token_minted
    assert_received :token_minted
    refute_received :token_minted
  end

  test "an unreadable response is an error, never a crash" do
    install_stub(fn conn, "/api/v1/airtime" -> respond(conn, 200, "not json") end)

    assert {:error, {:invalid_response, "not json"}} =
             Instalipa.send_airtime(%{phone: "254705340183", amount: "100"})
  end

  test "a rail error keeps the code a string and carries the message" do
    install_stub(fn conn, "/api/v1/airtime" ->
      respond(conn, 402, json(%{"error" => "insufficient_float", "message" => "Float is empty"}))
    end)

    assert {:error, {:instalipa, "insufficient_float", "Float is empty", 402}} =
             Instalipa.send_airtime(%{phone: "254705340183", amount: "100"})

    assert Instalipa.error_message({:instalipa, "insufficient_float", "Float is empty", 402}) ==
             "Float is empty"
  end

  test "with no credentials the client is not configured and refuses to send" do
    Application.put_env(:viewninjas, @config,
      base_url: "https://instalipa.test",
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    refute Instalipa.configured?()

    assert {:error, :not_configured} =
             Instalipa.send_airtime(%{phone: "254705340183", amount: "100"})

    assert Instalipa.error_message(:not_configured) =~ "not configured"
  end
end
