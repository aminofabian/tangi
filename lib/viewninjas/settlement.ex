defmodule ViewNinjas.Settlement do
  @moduledoc """
  Reconciling a Malipo settlement statement (scope.md §10; `docs/malipo-connect.md`
  §10; build-plan.md M10).

  The statement is the only outside view of two things our own rows cannot see:
  what the money cost to collect, and a payment the callback missed and the sweep
  gave up on. So it is landed raw, matched **inside its own window**, and put in
  one of four buckets:

  | Bucket | Meaning |
  | --- | --- |
  | `matched` | one line, one payment, the gross agrees |
  | `amount_mismatch` | found, but the gross differs |
  | `provider_only` | the statement has a payment we have no row for |
  | `local_only` | we believe it settled, and the statement has no line |

  **Nothing else is automatic.** On a `matched` line the reconciled fee is written
  onto the payment; every other bucket is a flag for a person, never an automatic
  ledger write — only a confirming `GET` settles a payment (scope.md §8).

  The statement format is not confirmed with Malipo yet, so the parser is a
  documented, minimal CSV: a header row naming the columns, one line per
  transaction. Confirm the shape before trusting a real file.
  """

  import Ecto.Query

  alias ViewNinjas.Payments
  alias ViewNinjas.Payments.Payment
  alias ViewNinjas.Repo
  alias ViewNinjas.Settlement.SettlementLine

  # Settlement day is not the sale day — M-Pesa settles next business day, so the
  # match window is the statement's period plus a margin.
  @margin_days 3
  @ref_headers ~w(malipo_id provider_ref)

  @doc """
  Parses a pasted statement into line maps with integer cents and a `Date`.

  Expects a header row; recognises `malipo_id`/`provider_ref`, `receipt`, `gross`,
  `fee`, `net` and `settled_on`. Rows without a reference are dropped.
  """
  @spec parse_csv(String.t()) :: {:ok, [map()]} | {:error, String.t()}
  def parse_csv(text) when is_binary(text) do
    case text |> String.split(~r/\r?\n/, trim: true) |> Enum.map(&split_row/1) do
      [] -> {:ok, []}
      [header | rows] -> build_lines(header, rows)
    end
  end

  def parse_csv(_text), do: {:error, "no statement pasted"}

  @doc """
  Lands a statement raw, classifies every line, and applies the matched fees.

  Returns the statement's buckets. A re-import is free: `(statement_id,
  provider_ref)` is unique, so the same line is never recorded twice.
  """
  @spec import(String.t(), [map()]) :: {:ok, map()} | {:error, term()}
  def import(statement_id, lines) when is_binary(statement_id) and is_list(lines) do
    window = statement_window(lines)

    Enum.each(lines, &land(statement_id, &1))
    Enum.each(lines_of(statement_id), &classify(&1, window))
    flag_local_only(statement_id, window)

    {:ok, buckets(statement_id)}
  end

  def import(_statement_id, _lines), do: {:error, :bad_statement}

  @doc "The stored lines of a statement, grouped into buckets with their sums."
  @spec buckets(String.t()) :: map()
  def buckets(statement_id) do
    lines = lines_of(statement_id)

    %{
      statement_id: statement_id,
      lines: lines,
      by_kind: Enum.group_by(lines, & &1.kind),
      counts: Enum.frequencies_by(lines, & &1.kind),
      gross_cents: sum(lines, :gross_cents),
      fee_cents: sum(lines, :fee_cents),
      net_cents: sum(lines, :net_cents)
    }
  end

  @doc """
  The payout delta: what the statement says should have landed, net of fees,
  against what the till or bank actually received. The one number that cannot be
  argued with (`docs/malipo-connect.md` §10).
  """
  @spec payout_delta(String.t(), integer()) :: integer()
  def payout_delta(statement_id, received_cents) when is_integer(received_cents) do
    buckets(statement_id).net_cents - received_cents
  end

  @doc "The statement ids that have been imported, newest first."
  @spec statements() :: [String.t()]
  def statements do
    SettlementLine
    |> group_by([l], l.statement_id)
    |> select([l], {l.statement_id, max(l.inserted_at)})
    |> order_by([l], desc: max(l.inserted_at))
    |> Repo.all()
    |> Enum.map(&elem(&1, 0))
  end

  # -- landing and classifying -------------------------------------------

  defp land(statement_id, line) do
    line
    |> Map.put("statement_id", statement_id)
    |> then(&SettlementLine.changeset(%SettlementLine{}, &1))
    |> Repo.insert(on_conflict: :nothing)
  end

  defp lines_of(statement_id) do
    Repo.all(
      from l in SettlementLine,
        where: l.statement_id == ^statement_id,
        order_by: [asc: l.id]
    )
  end

  # A line that is already a local-only flag is left alone.
  defp classify(%SettlementLine{kind: :local_only}, _window), do: :ok

  defp classify(%SettlementLine{} = line, window) do
    case find_payment(line, window) do
      nil -> mark(line, :provider_only, nil)
      %Payment{} = payment -> mark(line, kind_for(line, payment), payment)
    end
  end

  defp find_payment(%SettlementLine{provider_ref: ref, receipt: receipt}, window) do
    Payments.get_payment_by_malipo_id(ref) || Payments.get_by_receipt(receipt, window)
  end

  defp kind_for(%SettlementLine{gross_cents: nil}, _payment), do: :matched

  defp kind_for(%SettlementLine{gross_cents: gross}, %Payment{amount_cents: gross}),
    do: :matched

  defp kind_for(_line, _payment), do: :amount_mismatch

  defp mark(%SettlementLine{} = line, kind, payment) do
    {:ok, _line} = line |> Ecto.Changeset.change(kind: kind) |> Repo.update()
    if kind == :matched and payment, do: Payments.record_fee(payment, line.fee_cents)
    :ok
  end

  # A payment we believe settled that the statement never mentions is a flag, not
  # an accusation: it is usually the cut-off, or a refund already reversed.
  defp flag_local_only(statement_id, window) do
    {from, to} = window
    mentioned = mentioned_refs(statement_id)

    Payments.settled_between(from, to)
    |> Enum.reject(&MapSet.member?(mentioned, &1.malipo_payment_id))
    |> Enum.each(&land_local_only(statement_id, &1))
  end

  defp mentioned_refs(statement_id) do
    SettlementLine
    |> where([l], l.statement_id == ^statement_id)
    |> select([l], {l.provider_ref, l.receipt})
    |> Repo.all()
    |> Enum.flat_map(fn {ref, receipt} -> Enum.reject([ref, receipt], &is_nil/1) end)
    |> MapSet.new()
  end

  defp land_local_only(statement_id, %Payment{} = payment) do
    ref = payment.malipo_payment_id || "local-#{payment.id}"

    %SettlementLine{}
    |> SettlementLine.changeset(%{
      statement_id: statement_id,
      provider_ref: ref,
      receipt: payment.receipt,
      gross_cents: payment.amount_cents,
      fee_cents: payment.fee_cents,
      net_cents: nil,
      settled_on: DateTime.to_date(payment.inserted_at),
      kind: :local_only
    })
    |> Repo.insert(on_conflict: :nothing)
  end

  defp statement_window(lines) do
    dates = lines |> Enum.map(&Map.get(&1, "settled_on")) |> Enum.reject(&is_nil/1)

    {from_date, to_date} =
      case dates do
        [] -> {Date.utc_today(), Date.utc_today()}
        _ -> {Enum.min(dates), Enum.max(dates)}
      end

    {DateTime.new!(Date.add(from_date, -@margin_days), ~T[00:00:00]),
     DateTime.new!(Date.add(to_date, @margin_days + 1), ~T[00:00:00])}
  end

  # -- CSV ---------------------------------------------------------------

  defp build_lines(header, rows) do
    header = Enum.map(header, &normalize_header/1)

    case Enum.find_index(header, &(&1 in @ref_headers)) do
      nil ->
        {:error, "the statement needs a malipo_id or provider_ref column"}

      ref_at ->
        columns = %{
          ref: ref_at,
          receipt: Enum.find_index(header, &(&1 == "receipt")),
          gross: Enum.find_index(header, &(&1 == "gross")),
          fee: Enum.find_index(header, &(&1 == "fee")),
          net: Enum.find_index(header, &(&1 == "net")),
          settled_on: Enum.find_index(header, &(&1 == "settled_on"))
        }

        {:ok, rows |> Enum.map(&to_line(&1, columns)) |> Enum.reject(&is_nil/1)}
    end
  end

  defp to_line(row, columns) do
    ref = cell(row, columns.ref)

    if ref in [nil, ""] do
      nil
    else
      %{
        "provider_ref" => ref,
        "receipt" => blank_to_nil(cell(row, columns.receipt)),
        "gross_cents" => cents(cell(row, columns.gross)),
        "fee_cents" => cents(cell(row, columns.fee)),
        "net_cents" => cents(cell(row, columns.net)),
        "settled_on" => date(cell(row, columns.settled_on))
      }
    end
  end

  defp cell(_row, nil), do: nil
  defp cell(row, index), do: Enum.at(row, index)

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp normalize_header(header), do: header |> String.trim() |> String.downcase()

  # "1,250.00" -> 125_000 cents. Decimal keeps it integral, never a float.
  defp cents(nil), do: nil
  defp cents(""), do: nil

  defp cents(value) do
    cleaned = String.replace(value, ",", "")

    case Decimal.parse(cleaned) do
      {decimal, ""} ->
        decimal |> Decimal.mult(100) |> Decimal.round(0, :half_up) |> Decimal.to_integer()

      _ ->
        nil
    end
  end

  defp date(nil), do: nil
  defp date(""), do: nil

  defp date(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  # A minimal, quote-aware CSV row splitter: fields split on a bare comma, a `"`
  # opens a quoted field, and `""` inside it is a literal quote.
  defp split_row(line), do: parse_row(String.to_charlist(String.trim(line)), :field, [], [])

  defp parse_row([], _state, current, rows), do: Enum.reverse([field(current) | rows])

  defp parse_row([?", ?" | rest], :quoted, current, rows),
    do: parse_row(rest, :quoted, [?" | current], rows)

  defp parse_row([?" | rest], :quoted, current, rows), do: parse_row(rest, :field, current, rows)
  defp parse_row([?" | rest], :field, current, rows), do: parse_row(rest, :quoted, current, rows)

  defp parse_row([?, | rest], :field, current, rows),
    do: parse_row(rest, :field, [], [field(current) | rows])

  defp parse_row([char | rest], state, current, rows),
    do: parse_row(rest, state, [char | current], rows)

  defp field(chars), do: chars |> Enum.reverse() |> List.to_string() |> String.trim()

  defp sum(lines, field) do
    lines
    |> Enum.map(&Map.get(&1, field))
    |> Enum.reject(&is_nil/1)
    |> Enum.sum()
  end
end
