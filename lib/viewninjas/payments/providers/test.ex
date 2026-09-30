defmodule ViewNinjas.Payments.Providers.Test do
  @moduledoc """
  An in-memory stand-in for Malipo in tests (mirrors `Sms.Providers.Test`).

  `create/1` records the attempt and returns a `pending` payment whose id is
  derived from the idempotency key, so re-sending a key returns the original
  payment. A test then drives the outcome with `settle!/2` or `fail!/3` before
  running the confirming job. State lives in ETS owned by
  `ViewNinjas.Payments.Outbox`, so it survives between tests; ids are unique per
  attempt, so that is harmless.
  """

  @behaviour ViewNinjas.Payments.Provider

  @table :vn_payments_test

  @doc "The ETS table this provider uses."
  def table, do: @table

  @impl true
  def create(attrs) do
    case rejection(attrs.idempotency_key) do
      nil -> maybe_create(attrs)
      reason -> {:error, reason}
    end
  end

  @impl true
  def get(id) do
    case :ets.lookup(@table, {:payment, id}) do
      [{{:payment, ^id}, payment}] -> {:ok, payment}
      [] -> {:error, {:malipo, "not_found", "no such payment", 404}}
    end
  end

  @doc "Marks a payment settled, as a confirming GET would report it."
  def settle!(id, receipt \\ "TESTRECEIPT") do
    update!(id, &%{&1 | status: :settled, receipt: receipt})
  end

  @doc "Marks a payment failed, as Malipo reports a declined prompt."
  def fail!(id, kind \\ "customer_timeout", message \\ "The customer did not enter a PIN.") do
    update!(id, &%{&1 | status: :failed, failure_kind: kind, failure_message: message})
  end

  @doc "Overrides the amount the rail reports, to test the attempt check (M12)."
  def set_amount!(id, amount), do: update!(id, &%{&1 | amount: amount})

  @doc """
  Makes `create/1` reject the given idempotency key, so the create-failure path
  can be tested. Keyed on the key, so concurrent tests cannot steal it.
  """
  def reject_create!(
        idempotency_key,
        reason \\ {:malipo, "rail_failure", "M-Pesa rejected the prompt", 422}
      ) do
    :ets.insert(@table, {{:reject, idempotency_key}, reason})
  end

  @doc "Every payment `create/1` has returned."
  def created do
    @table
    |> :ets.match_object({{:created, :_}, :_})
    |> Enum.map(fn {{:created, _id}, payment} -> payment end)
  end

  @doc "The payments created for one idempotency key."
  def created_for(idempotency_key) do
    Enum.filter(created(), &(&1.idempotency_key == idempotency_key))
  end

  defp maybe_create(attrs) do
    id = id_for(attrs.idempotency_key)

    case :ets.lookup(@table, {:payment, id}) do
      [{{:payment, ^id}, existing}] ->
        # The same key returns the original payment, never a second prompt.
        {:ok, existing}

      [] ->
        payment = %{
          id: id,
          status: :pending,
          amount: attrs.amount,
          currency: "KES",
          receipt: nil,
          failure_kind: nil,
          failure_message: nil,
          customer_phone: attrs.customer_phone,
          idempotency_key: attrs.idempotency_key,
          reference: attrs[:reference]
        }

        :ets.insert(@table, {{:payment, id}, payment})
        :ets.insert(@table, {{:created, id}, payment})
        {:ok, payment}
    end
  end

  defp update!(id, fun) do
    case :ets.lookup(@table, {:payment, id}) do
      [{{:payment, ^id}, payment}] -> :ets.insert(@table, {{:payment, id}, fun.(payment)})
      [] -> raise ArgumentError, "no test payment #{inspect(id)}"
    end
  end

  defp rejection(idempotency_key) do
    case :ets.lookup(@table, {:reject, idempotency_key}) do
      [{{:reject, _key}, reason}] -> reason
      [] -> nil
    end
  end

  defp id_for(idempotency_key) do
    digest = :crypto.hash(:sha256, idempotency_key) |> Base.encode16(case: :lower)
    "test-" <> binary_part(digest, 0, 16)
  end
end
