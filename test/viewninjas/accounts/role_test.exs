defmodule ViewNinjas.Accounts.RoleTest do
  use ExUnit.Case, async: true

  alias ViewNinjas.Accounts.Role

  doctest ViewNinjas.Accounts.Role

  test "all/0 is the stored set, in order" do
    assert Role.all() == [:customer, :admin, :super_admin]
  end

  test "staff?/1 covers admin and super_admin" do
    assert Role.staff?(:admin)
    assert Role.staff?(:super_admin)
    refute Role.staff?(:customer)
    refute Role.staff?(nil)
  end

  test "super_admin?/1 is only the money-knob role" do
    assert Role.super_admin?(:super_admin)
    refute Role.super_admin?(:admin)
    refute Role.super_admin?(:customer)
  end

  test "parse/1 accepts atoms and strings" do
    assert Role.parse(:admin) == {:ok, :admin}
    assert Role.parse("super_admin") == {:ok, :super_admin}
    assert Role.parse("customer") == {:ok, :customer}
  end

  test "parse/1 rejects anything else" do
    assert Role.parse("root") == :error
    assert Role.parse("Admin") == :error
    assert Role.parse(nil) == :error
    assert Role.parse(123) == :error
  end
end
