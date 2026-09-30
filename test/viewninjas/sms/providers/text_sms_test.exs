defmodule ViewNinjas.Sms.Providers.TextSmsTest do
  # Mutates global SMS config, so keep this file serial. It reads the settings
  # store now, so it needs the sandbox.
  use ViewNinjas.DataCase, async: false

  alias ViewNinjas.Sms.Providers.TextSms

  setup do
    previous = Application.get_env(:viewninjas, :sms)
    on_exit(fn -> Application.put_env(:viewninjas, :sms, previous) end)

    Application.put_env(:viewninjas, :sms,
      provider: ViewNinjas.Sms.Providers.Test,
      api_key: "test-key",
      partner_id: "1234",
      shortcode: "VNI",
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    :ok
  end

  test "sends the expected payload and parses the reference" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert {"content-type", "application/json"} in conn.req_headers
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      assert payload["apikey"] == "test-key"
      assert payload["partnerID"] == "1234"
      assert payload["shortcode"] == "VNI"
      assert payload["mobile"] == "254712345678"
      assert payload["message"] =~ "123456"

      Req.Test.json(conn, %{
        "responses" => [
          %{
            "respid" => 1,
            "response-code" => 200,
            "response-description" => "Success",
            "mobile" => "254712345678",
            "messageid" => "TS-abc123"
          }
        ]
      })
    end)

    assert {:ok, result} = TextSms.send_sms("254712345678", "Your code is 123456")
    assert result.provider_ref == "TS-abc123"
    assert result.status == :sent
    assert result.cost_micros == nil
  end

  test "reports a rejection from the provider" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "responses" => [
          %{"respid" => 1, "response-code" => 401, "response-description" => "Invalid API key"}
        ]
      })
    end)

    assert {:error, {:provider_rejected, "Invalid API key"}} =
             TextSms.send_sms("254712345678", "hi")
  end

  test "surfaces a non-200 as an error" do
    Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    assert {:error, {:unexpected_response, 500, _body}} =
             TextSms.send_sms("254712345678", "hi")
  end

  test "fails clearly when the provider is not configured" do
    Application.put_env(:viewninjas, :sms, provider: ViewNinjas.Sms.Providers.Test, api_key: nil)

    assert TextSms.send_sms("254712345678", "hi") == {:error, :sms_not_configured}
  end
end
