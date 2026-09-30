defmodule ViewNinjas.Accounts.PhoneTest do
  use ExUnit.Case, async: true

  alias ViewNinjas.Accounts.Phone

  doctest ViewNinjas.Accounts.Phone

  describe "normalize/1" do
    test "collapses every common spelling to one canonical form" do
      canonical = "254712345678"

      inputs = [
        "254712345678",
        "0712345678",
        "+254712345678",
        "712345678",
        "0712 345 678",
        "+254 712 345 678",
        "254 712 345 678",
        "0712-345-678",
        "(0712) 345 678",
        "+254-712-345-678",
        "  0712345678  ",
        "00254712345678",
        "254.712.345.678"
      ]

      for input <- inputs do
        assert {:ok, ^canonical} = Phone.normalize(input),
               "expected #{inspect(input)} to normalize to #{canonical}"
      end
    end

    test "accepts the 01 mobile range too" do
      assert {:ok, "254112345678"} = Phone.normalize("0112345678")
      assert {:ok, "254112345678"} = Phone.normalize("+254112345678")
      assert {:ok, "254112345678"} = Phone.normalize("112345678")
    end

    test "is idempotent" do
      for input <- ["0712345678", "+254712345678", "712345678", "254712345678"] do
        {:ok, canonical} = Phone.normalize(input)
        assert {:ok, ^canonical} = Phone.normalize(canonical)
      end
    end

    test "rejects anything that is not a Kenyan mobile" do
      inputs = [
        nil,
        "",
        "   ",
        "12345",
        "071234567",
        "07123456789",
        "254812345678",
        "0812345678",
        "812345678",
        "1234567890",
        "+15551234567",
        "abc",
        "0712 345 67a",
        "2547123456789",
        "+",
        42,
        %{}
      ]

      for input <- inputs do
        assert {:error, :invalid_phone} = Phone.normalize(input),
               "expected #{inspect(input)} to be rejected"
      end
    end
  end

  describe "valid?/1" do
    test "is true only for normalizable numbers" do
      assert Phone.valid?("0712345678")
      refute Phone.valid?("12345")
      refute Phone.valid?(nil)
    end
  end

  describe "format/1" do
    test "renders a readable number, whatever the input spelling" do
      assert Phone.format("254712345678") == "+254 712 345 678"
      assert Phone.format("0712 345 678") == "+254 712 345 678"
      assert Phone.format("not a phone") == "not a phone"
    end
  end

  describe "normalize_or_self/1" do
    test "passes through what it cannot parse" do
      assert Phone.normalize_or_self("0712345678") == "254712345678"
      assert Phone.normalize_or_self("nope") == "nope"
      assert Phone.normalize_or_self(nil) == nil
    end
  end
end
