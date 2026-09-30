defmodule ViewNinjas.LinksTest do
  @moduledoc """
  The one gate for customer links (scope.md §13).
  """

  use ExUnit.Case, async: true

  alias ViewNinjas.Links

  doctest ViewNinjas.Links

  test "accepts an https profile link and trims it" do
    assert Links.validate("  https://instagram.com/viewninjas  ") ==
             {:ok, "https://instagram.com/viewninjas"}
  end

  test "refuses a non-https scheme" do
    assert {:error, message} = Links.validate("http://instagram.com/x")
    assert message =~ "https"
  end

  test "refuses a scheme-relative or schemeless value" do
    assert {:error, _} = Links.validate("instagram.com/x")
    assert {:error, _} = Links.validate("//instagram.com/x")
    assert {:error, _} = Links.validate("javascript:alert(1)")
  end

  test "refuses a blank value with a human sentence" do
    assert {:error, "Enter the link you want us to grow."} = Links.validate("")
    assert {:error, _} = Links.validate(nil)
  end

  test "refuses an over-long link" do
    long = "https://instagram.com/" <> String.duplicate("a", Links.max_length())
    assert {:error, message} = Links.validate(long)
    assert message =~ "#{Links.max_length()}"
  end

  test "valid?/1 agrees with validate/1" do
    assert Links.valid?("https://example.com/x")
    refute Links.valid?("ftp://example.com/x")
  end
end
