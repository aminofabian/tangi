defmodule ViewNinjas.Orders.SupplierStatusTest do
  @moduledoc """
  Mapping a panel's words onto our states (scope.md §10).
  """

  use ExUnit.Case, async: true

  alias ViewNinjas.Orders.SupplierStatus

  test "maps the words the panels actually use" do
    assert SupplierStatus.map("Awaiting") == :placed
    assert SupplierStatus.map("Pending") == :placed
    assert SupplierStatus.map("In progress") == :in_progress
    assert SupplierStatus.map("Processing") == :in_progress
    assert SupplierStatus.map("Completed") == :completed
    assert SupplierStatus.map("Partial") == :partial
    assert SupplierStatus.map("Canceled") == :canceled
    assert SupplierStatus.map("Refunded") == :canceled
  end

  test "is case and whitespace insensitive" do
    assert SupplierStatus.map("  in PROGRESS ") == :in_progress
    assert SupplierStatus.map("COMPLETED") == :completed
  end

  test "an unknown word is not guessed at" do
    assert SupplierStatus.map("awaiting_verification") == nil
    assert SupplierStatus.map(nil) == nil
    assert SupplierStatus.map(42) == nil
  end
end
