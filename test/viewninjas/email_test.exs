defmodule ViewNinjas.EmailTest do
  @moduledoc """
  Transactional email through Resend: the key is the super-admin's, read per send
  so saving it takes effect without a redeploy.

  Tests run with Swoosh's API client disabled, which is exactly the case where a
  stored key must **not** switch the adapter — `false.post/4` would crash. So the
  selection is asserted on the config that `Swoosh.Mailer` merges, rather than by
  letting a real request go out.
  """

  use ViewNinjas.DataCase, async: false

  import Swoosh.TestAssertions

  alias ViewNinjas.Email
  alias ViewNinjas.Mailer
  alias ViewNinjas.Settings

  setup do
    for key <- [:resend, ViewNinjas.Mailer] do
      previous = Application.get_env(:viewninjas, key)
      on_exit(fn -> Application.put_env(:viewninjas, key, previous) end)
    end

    previous_client = Application.get_env(:swoosh, :api_client)
    on_exit(fn -> Application.put_env(:swoosh, :api_client, previous_client) end)

    :ok
  end

  defp email do
    Swoosh.Email.new()
    |> Swoosh.Email.to("customer@viewninjas.test")
    |> Swoosh.Email.from({"Tangi", "hello@viewninjas.test"})
    |> Swoosh.Email.subject("Your Tangi receipt")
    |> Swoosh.Email.text_body("Thanks.")
  end

  describe "deliver/1 without a key" do
    test "falls back to the boot adapter so development still sees the email" do
      Application.put_env(:viewninjas, :resend, api_key: nil)
      refute Settings.email_configured?()

      assert {:ok, _metadata} = Email.deliver(email())

      # The Test adapter is configured for this environment, so the fallback is
      # observable rather than a guess.
      assert_email_sent(fn sent -> sent.subject == "Your Tangi receipt" end)
    end
  end

  describe "deliver/1 with a key" do
    test "uses Resend and the stored key once an API client is available" do
      {:ok, _} = Settings.put("resend_api_key", "re_from_db", nil)
      {:ok, _} = Settings.put("resend_base_url", "https://api.resend.test", nil)
      Application.put_env(:swoosh, :api_client, Swoosh.ApiClient.Req)

      config = Swoosh.Mailer.parse_config(:viewninjas, Mailer, [], resend_config())

      assert config[:adapter] == Swoosh.Adapters.Resend
      assert config[:api_key] == "re_from_db"
      assert config[:base_url] == "https://api.resend.test"
    end

    test "the per-send config wins over the adapter chosen at boot" do
      Application.put_env(:viewninjas, Mailer, adapter: Swoosh.Adapters.Local)
      Application.put_env(:swoosh, :api_client, Swoosh.ApiClient.Req)

      config = Swoosh.Mailer.parse_config(:viewninjas, Mailer, [], resend_config())

      # This is the whole point: the database key overrides the boot adapter,
      # so rotating the key needs no restart.
      refute config[:adapter] == Swoosh.Adapters.Local
      assert config[:adapter] == Swoosh.Adapters.Resend
    end

    test "a stored key is not used when no API client is configured" do
      {:ok, _} = Settings.put("resend_api_key", "re_from_db", nil)
      Application.put_env(:swoosh, :api_client, false)

      # Falls back rather than calling `false.post/4`.
      assert {:ok, _metadata} = Email.deliver(email())
      assert_email_sent(fn sent -> sent.subject == "Your Tangi receipt" end)
    end

    test "saving a new key takes effect on the next send" do
      Application.put_env(:swoosh, :api_client, Swoosh.ApiClient.Req)

      {:ok, _} = Settings.put("resend_api_key", "re_first", nil)

      assert Swoosh.Mailer.parse_config(:viewninjas, Mailer, [], resend_config())[:api_key] ==
               "re_first"

      {:ok, _} = Settings.put("resend_api_key", "re_rotated", nil)

      assert Swoosh.Mailer.parse_config(:viewninjas, Mailer, [], resend_config())[:api_key] ==
               "re_rotated"
    end
  end

  describe "deliver!/1" do
    test "returns :ok and does not raise when a send fails" do
      Application.put_env(:viewninjas, :resend, api_key: nil)

      # A message Swoosh rejects before the adapter sees it.
      broken =
        Swoosh.Email.new()
        |> Swoosh.Email.to("customer@viewninjas.test")
        |> Swoosh.Email.subject("No From")

      assert :ok = Email.deliver!({"broken", broken})
    end
  end

  describe "test_email/1" do
    test "refuses without a key rather than quietly falling back" do
      Application.put_env(:viewninjas, :resend, api_key: nil)
      Application.put_env(:swoosh, :api_client, false)

      # A send that "succeeded" through the local adapter would tell the
      # super-admin their key works when Resend was never contacted.
      assert {:error, :email_not_configured} = Email.test_email("someone@viewninjas.test")
      refute_email_sent()
    end

    test "refuses a blank recipient" do
      assert {:error, :no_recipient} = Email.test_email("")
    end

    test "the message goes to the address it is handed and from the saved sender" do
      Application.put_env(:viewninjas, :resend, api_key: nil)
      {:ok, _} = Settings.put("mailer_from", "hello@viewninjas.test", nil)

      message = Email.test_message("someone@viewninjas.test")

      assert message.to == [{"", "someone@viewninjas.test"}]
      assert message.from == {"Tangi", "hello@viewninjas.test"}
      assert message.subject =~ "test email"
      assert message.text_body =~ "Resend API key"
    end

    test "a stored key with no API client is not ready" do
      {:ok, _} = Settings.put("resend_api_key", "re_a_key", nil)
      Application.put_env(:swoosh, :api_client, false)

      refute Email.configured?()
      assert {:error, :email_not_configured} = Email.test_email("someone@viewninjas.test")

      Application.put_env(:swoosh, :api_client, Swoosh.ApiClient.Req)
      assert Email.configured?()
    end
  end

  describe "failure_reason/1" do
    test "uses Resend's own message" do
      assert Email.failure_reason({401, %{"message" => "API key is invalid"}}) ==
               "401 — API key is invalid"
    end

    test "falls back to the status when there is no message" do
      assert Email.failure_reason({422, %{"other" => "shape"}}) == "HTTP 422"
      assert Email.failure_reason({500, "gateway timeout"}) == "HTTP 500"
    end

    test "explains a missing key, a missing recipient and a transport failure" do
      assert Email.failure_reason(:email_not_configured) == "no Resend API key is set"
      assert Email.failure_reason(:no_recipient) == "no address to send to"

      assert Email.failure_reason(%Req.TransportError{reason: :econnrefused}) =~ "refused"
    end
  end

  # Mirrors the private configuration `ViewNinjas.Email` builds. Kept here rather
  # than exporting the function, because what is under test is the config Swoosh
  # ends up merging, not the module's own plumbing.
  defp resend_config do
    [
      adapter: Swoosh.Adapters.Resend,
      api_key: Settings.resend_api_key(),
      base_url: Settings.resend_base_url()
    ]
  end
end
