defmodule ViewNinjasWeb.SmsCallbackControllerTest do
  use ViewNinjasWeb.ConnCase, async: true

  import ViewNinjas.AccountsFixtures

  alias ViewNinjas.Repo
  alias ViewNinjas.Sms
  alias ViewNinjas.Sms.SmsMessage

  setup do
    {:ok, message} = Sms.send_message(%{to: unique_user_phone(), template: "test", body: "x"})
    %{message: message}
  end

  test "marks a message delivered", %{conn: conn, message: message} do
    conn =
      post(conn, ~p"/webhooks/textsms/sms", %{
        "messageid" => message.provider_ref,
        "status" => "Delivered"
      })

    assert response(conn, 200) == "ok"
    assert Repo.get!(SmsMessage, message.id).status == :delivered
  end

  test "marks a rejection as failed", %{conn: conn, message: message} do
    post(conn, ~p"/webhooks/textsms/sms", %{
      "messageid" => message.provider_ref,
      "status" => "Failed"
    })

    assert Repo.get!(SmsMessage, message.id).status == :failed
  end

  test "accepts the response-description field as a status", %{conn: conn, message: message} do
    post(conn, ~p"/webhooks/textsms/sms", %{
      "messageId" => message.provider_ref,
      "response-description" => "Success"
    })

    assert Repo.get!(SmsMessage, message.id).status == :delivered
  end

  test "acknowledges an unknown reference", %{conn: conn} do
    conn =
      post(conn, ~p"/webhooks/textsms/sms", %{"messageid" => "unknown", "status" => "Delivered"})

    assert response(conn, 200) == "ok"
  end

  test "ignores a body it cannot use", %{conn: conn} do
    conn = post(conn, ~p"/webhooks/textsms/sms", %{"something" => "else"})

    assert response(conn, 200) == "ignored"
  end
end
