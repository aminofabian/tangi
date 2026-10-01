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

  describe "network/1" do
    test "places each published range" do
      assert Phone.network("0700 000 111") == :safaricom
      assert Phone.network("0729 000 111") == :safaricom
      assert Phone.network("0740 000 111") == :safaricom
      assert Phone.network("0743 000 111") == :safaricom
      assert Phone.network("0790 000 111") == :safaricom
      assert Phone.network("0799 000 111") == :safaricom
      assert Phone.network("0110 000 111") == :safaricom
      assert Phone.network("0119 000 111") == :safaricom

      assert Phone.network("0730 000 111") == :airtel
      assert Phone.network("0739 000 111") == :airtel
      assert Phone.network("0750 000 111") == :airtel
      assert Phone.network("0756 000 111") == :airtel
      assert Phone.network("0780 000 111") == :airtel
      assert Phone.network("0789 000 111") == :airtel
      assert Phone.network("0100 000 111") == :airtel
      assert Phone.network("0109 000 111") == :airtel

      assert Phone.network("0770 000 111") == :telkom
      assert Phone.network("0779 000 111") == :telkom
      assert Phone.network("0120 000 111") == :telkom
      assert Phone.network("0129 000 111") == :telkom

      assert Phone.network("0747 000 111") == :faiba
    end

    test "does not leak across a boundary" do
      # 0729 is Safaricom and 0730 Airtel; 0743 Safaricom, 0744 nothing, 0747 Faiba.
      assert Phone.network("0729 000 111") == :safaricom
      assert Phone.network("0730 000 111") == :airtel
      assert Phone.network("0743 000 111") == :safaricom
      assert Phone.network("0744 000 111") == nil
      assert Phone.network("0746 000 111") == nil
      assert Phone.network("0747 000 111") == :faiba
      assert Phone.network("0748 000 111") == nil
    end

    test "says nothing rather than guessing" do
      # 0763 is Equitel, a valid number that is not on the published list.
      assert Phone.network("0763 000 111") == nil
      assert Phone.network("12345") == nil
      assert Phone.network(nil) == nil
    end

    test "every network it names has a display name" do
      assert Phone.networks() == [:safaricom, :airtel, :telkom, :faiba]

      for network <- Phone.networks() do
        assert is_binary(Phone.network_name(network))
      end

      assert Phone.network_name(:nothing) == nil
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
