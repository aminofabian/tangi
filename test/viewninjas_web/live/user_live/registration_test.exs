defmodule ViewNinjasWeb.UserLive.RegistrationTest do
  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures

  alias ViewNinjas.Accounts

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Create an account"
      assert html =~ "Log in"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/register")
        |> follow_redirect(conn, ~p"/")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(
          user: %{"email" => "with spaces", "phone" => "123", "password" => "short"}
        )

      assert result =~ "Create an account"
      assert result =~ "must have the @ sign and no spaces"
      assert result =~ "is not a valid Kenyan number"
      assert result =~ "should be at least 12 character(s)"
    end
  end

  describe "register user" do
    test "creates a confirmed customer and hands off to log in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      html =
        lv
        |> form("#registration_form",
          user: %{
            "email" => email,
            "phone" => "0712 345 678",
            "password" => valid_user_password(),
            "password_confirmation" => valid_user_password()
          }
        )
        |> render_submit()

      user = Accounts.get_user_by_email(email)
      assert user
      assert user.phone == "254712345678"
      assert user.role == :customer
      assert user.confirmed_at
      assert user.hashed_password

      # Sign-up cannot set a session, so it hands the credentials to the
      # session controller for a frictionless log in.
      assert has_element?(lv, "#registration_login")
      assert html =~ email
    end

    test "renders errors for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      user = user_fixture(%{email: "test@email.com"})

      result =
        lv
        |> form("#registration_form",
          user: %{
            "email" => user.email,
            "phone" => unique_user_phone(),
            "password" => valid_user_password(),
            "password_confirmation" => valid_user_password()
          }
        )
        |> render_submit()

      assert result =~ "has already been taken"
    end

    test "rejects a duplicate phone number", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      user = user_fixture()

      result =
        lv
        |> form("#registration_form",
          user: %{
            "email" => unique_user_email(),
            "phone" => user.phone,
            "password" => valid_user_password(),
            "password_confirmation" => valid_user_password()
          }
        )
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end

  describe "registration navigation" do
    test "redirects to login page when the Log in button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Log in")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert login_html =~ "Log in"
    end
  end
end
