defmodule Mix.Tasks.Viewninjas.SuppliersSetupTest do
  # Mutates the environment, so keep this file serial.
  use ViewNinjas.DataCase, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Viewninjas.Suppliers.Setup
  alias ViewNinjas.Suppliers

  setup do
    previous = System.get_env("SECSERS_API_KEY")

    on_exit(fn ->
      if previous do
        System.put_env("SECSERS_API_KEY", previous)
      else
        System.delete_env("SECSERS_API_KEY")
      end
    end)

    :ok
  end

  test "creates the panel from the environment and is idempotent" do
    System.put_env("SECSERS_API_KEY", "key-from-env")

    output = capture_io(fn -> Setup.run(["--activate"]) end)

    assert output =~ "secsers: active"

    supplier = Suppliers.get_supplier_by_slug("secsers")
    assert supplier.api_key == "key-from-env"
    assert supplier.active

    # Rotating the key updates the same row rather than adding another.
    System.put_env("SECSERS_API_KEY", "rotated-key")
    capture_io(fn -> Setup.run([]) end)

    assert Suppliers.get_supplier_by_slug("secsers").api_key == "rotated-key"
    assert Suppliers.list_suppliers() |> length() == 1
  end

  test "skips a panel with no key in the environment" do
    System.delete_env("SECSERS_API_KEY")

    output = capture_io(fn -> Setup.run([]) end)

    assert output =~ "secsers: skipped"
    assert is_nil(Suppliers.get_supplier_by_slug("secsers"))
  end
end
