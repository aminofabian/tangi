defmodule Mix.Tasks.Viewninjas.CreateAdminTest do
  use ViewNinjas.DataCase, async: false

  import ExUnit.CaptureIO
  import ViewNinjas.AccountsFixtures

  alias Mix.Tasks.Viewninjas.CreateAdmin
  alias ViewNinjas.Accounts

  test "creates an admin with a canonical phone" do
    email = unique_user_email()

    output =
      capture_io(fn ->
        CreateAdmin.run([
          "--email",
          email,
          "--phone",
          "0712 345 678",
          "--password",
          valid_user_password(),
          "--role",
          "admin"
        ])
      end)

    assert output =~ "Created admin #{email}"

    user = Accounts.get_user_by_email(email)
    assert user.role == :admin
    assert user.phone == "254712345678"
    assert user.confirmed_at
  end

  test "creates a super admin" do
    email = unique_user_email()

    capture_io(fn ->
      CreateAdmin.run([
        "--email",
        email,
        "--phone",
        unique_user_phone(),
        "--password",
        valid_user_password(),
        "--role",
        "super_admin"
      ])
    end)

    assert Accounts.get_user_by_email(email).role == :super_admin
  end

  test "refuses to create a customer" do
    assert_raise Mix.Error, ~r/--role must be admin or super_admin/, fn ->
      CreateAdmin.run([
        "--email",
        unique_user_email(),
        "--phone",
        unique_user_phone(),
        "--password",
        valid_user_password(),
        "--role",
        "customer"
      ])
    end
  end

  test "requires every option" do
    assert_raise Mix.Error, ~r/Missing required option/, fn ->
      CreateAdmin.run(["--email", unique_user_email()])
    end
  end
end
