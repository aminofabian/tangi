defmodule ViewNinjas.Catalog.TargetTest do
  @moduledoc """
  The target dimension on an offer: what the customer's link points at.

  This exists because platform and outcome were not enough — Facebook page likes
  and Facebook post likes are the same platform and the same outcome, and the
  unique index made the second one unpublishable.
  """

  use ExUnit.Case, async: true

  alias ViewNinjas.Catalog.Target

  describe "summary/2" do
    test "names the two products that used to collide" do
      assert Target.summary("page", "likes") == "Page Likes"
      assert Target.summary("post", "likes") == "Post Likes"
    end

    test "an empty target leaves just the outcome" do
      assert Target.summary("", "followers") == "Followers"
      assert Target.summary(nil, "views") == "Views"
    end

    test "a missing outcome still names the target" do
      assert Target.summary("reel", nil) == "Reel"
    end

    test "says nothing when there is nothing to say" do
      assert Target.summary("", nil) == ""
    end
  end

  describe "parse/1" do
    test "round-trips every known target" do
      for target <- Target.all() do
        assert {:ok, ^target} = Target.parse(Atom.to_string(target))
      end
    end

    test "refuses anything else" do
      assert Target.parse("banana") == :error
      assert Target.parse(nil) == :error
      assert Target.parse(42) == :error
    end
  end

  describe "valid?/1" do
    test "an empty target is valid — it means 'not set', not 'wrong'" do
      assert Target.valid?("")
      assert Target.valid?(nil)
    end

    test "a known target is valid and a made-up one is not" do
      assert Target.valid?("page")
      refute Target.valid?("banana")
      refute Target.valid?(:page)
    end
  end
end
