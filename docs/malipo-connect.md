# Malipo Connect — payments setup

One request puts an M-Pesa prompt on the customer's phone. When they enter their PIN, the money lands in the till, paybill, or bank you confirmed. You do not create a Daraja app, and you do not register a webhook.

- Point Connect at the money and take the key
- Create a payment
- Wait for it to settle
- Callbacks
- Verify the callback (optional)
- Reference

---

## 1. Point Connect at the money and take the key

In Malipo Connect, enter where money should land and confirm it. The next screen shows a ready-made request; the key inside it starts with `sk_live_`.

Send that key on every request:

```
Authorization: Bearer sk_live_…
```

The key is shown once. If you lose it, rotate it in Connect — the old key stops working immediately.

The base URL is the one Connect copied for you. In production that is `https://api.kiosk.ke`.

Keep the key in the environment (`MALIPO_SECRET_KEY`), never in the repo. If you verify callbacks you also hold a signing secret, `whsec_…` (`MALIPO_WEBHOOK_SECRET`).

---

## 2. Create the payment

`POST /v1/payments` sends the prompt to the customer's phone.

```bash
curl -X POST https://api.kiosk.ke/v1/payments \
  -H "Authorization: Bearer sk_live_…" \
  -H "Content-Type: application/json" \
  -d '{
    "amount": "100.00",
    "customer_phone": "254712345678",
    "idempotency_key": "order-1042-1",
    "reference": "order-1042"
  }'
```

`201 Created`:

```json
{
  "id": "8f3a1c2e-4b5d-4e6f-9a0b-1c2d3e4f5a6b",
  "status": "pending",
  "amount": "100.00",
  "currency": "KES",
  "reference": "order-1042",
  "receipt": null,
  "failure_kind": null,
  "failure_message": null
}
```

`status` starts at `pending`: the prompt is on their phone. It stays open for about 90 seconds. After that, a payment the customer did not complete becomes `failed`.

Sending the same `idempotency_key` again does not prompt the phone a second time. You get `200 OK` with the original payment.

---

## 3. Wait for it to settle

Poll until the payment leaves `pending`:

```bash
curl https://api.kiosk.ke/v1/payments/8f3a1c2e-4b5d-4e6f-9a0b-1c2d3e4f5a6b \
  -H "Authorization: Bearer sk_live_…"
```

Treat the payment as paid only when a GET returns `"status": "settled"`. When it does, `receipt` is the M-Pesa receipt code.

The whole thing in one function, with a bound so it cannot loop forever:

```js
const BASE = "https://api.kiosk.ke";
const headers = {
  authorization: "Bearer " + process.env.MALIPO_SECRET_KEY, // your sk_live_…
  "content-type": "application/json",
};

// 1. Create. Reusing this idempotency_key on a retry is safe: no second prompt.
let payment = await fetch(BASE + "/v1/payments", {
  method: "POST",
  headers,
  body: JSON.stringify({
    amount: "100.00",
    customer_phone: "254712345678",
    idempotency_key: "order-1042-1",
    reference: "order-1042",
  }),
}).then((res) => res.json());

// 2. Poll until it leaves pending, and stop once the prompt window has passed.
const deadline = Date.now() + 120_000; // the prompt lives about 90s
while (payment.status === "pending" && Date.now() < deadline) {
  await new Promise((resolve) => setTimeout(resolve, 3000));
  const res = await fetch(BASE + "/v1/payments/" + payment.id, { headers });
  if (res.status === 401) throw new Error("Malipo key rejected");
  if (!res.ok) continue; // transient; keep trying until the deadline
  payment = await res.json();
}

// 3. Paid only when that GET said settled.
if (payment.status === "settled") {
  order.markPaid(payment.receipt); // M-Pesa receipt code
} else {
  order.showError(payment.failure_message);
}
```

That is the whole integration. The rest of this page is reference.

---

## 4. Status

| Status | Meaning |
| --- | --- |
| `pending` | The prompt is on their phone, or Malipo is still waiting for M-Pesa. |
| `settled` | They paid. `receipt` is the M-Pesa receipt code. |
| `failed` | They cancelled, timed out, or M-Pesa rejected the prompt. Read `failure_kind` and `failure_message`. |

A payment only moves `pending → settled` or `pending → failed`. Both are terminal; there is no going back.

---

## 5. Callbacks instead of polling

If you would rather be pushed the result, send an `https` `callback_url` when you create the payment. Malipo POSTs there when the payment settles or fails, and retries if your server does not answer `2xx` quickly.

```json
{
  "id": "evt_8f3a1c2e4b5d4e6f9a0b1c2d3e4f5a6b",
  "event": "payment.settled",
  "created_at": "2026-09-29T07:41:00Z",
  "data": {
    "id": "8f3a1c2e-4b5d-4e6f-9a0b-1c2d3e4f5a6b",
    "amount": "100.00",
    "currency": "KES",
    "reference": "order-1042",
    "status": "settled",
    "receipt": "QKH7XYZ123"
  }
}
```

A failure sends `"event": "payment.failed"`, `"status": "failed"`, with `failure_kind` and `failure_message` instead of `receipt`.

When the POST arrives, call `GET /v1/payments/{id}` with `data.id` and follow the same rule: mark the order paid only if that GET returns `settled`. The delivery is a notification, not the source of truth. Answer `2xx` before you do anything slow, or Malipo will retry.

`callback_url` must be `https`. `http://localhost` and `http://127.0.0.1` are accepted so you can test on your own machine.

---

## 6. Verify the callback (optional)

Every callback is signed, so you can check it really came from Malipo. Take an HMAC-SHA256 of the raw request body using your webhook signing secret (the `whsec_…` shown in Connect), and compare it to the `X-Malipo-Signature` header:

```
X-Malipo-Signature: sha256=<hex digest>
```

In Node:

```js
import { createHmac, timingSafeEqual } from "node:crypto";

const expected = createHmac("sha256", process.env.MALIPO_WEBHOOK_SECRET)
  .update(rawBody) // the exact bytes you received, not a re-serialized object
  .digest();
const got = Buffer.from(
  (req.get("x-malipo-signature") || "").replace(/^sha256=/, ""),
  "hex"
);

if (got.length !== expected.length || !timingSafeEqual(got, expected)) {
  return res.sendStatus(400);
}
```

Verifying is optional, and it only proves the body is Malipo's. It does not prove the payment is final, so you still confirm with `GET /v1/payments/{id}` — treating the payment as paid only when it returns `settled` — and that alone is enough.

---

## 7. Reference

### Request fields

| Field | Required | What to send |
| --- | --- | --- |
| `amount` | yes | Shillings, as a decimal string greater than zero. `"100.00"`. |
| `customer_phone` | yes | A Kenyan mobile number. `254712345678`, `0712345678`, and `712345678` are the same number. `07…` and `01…` both work. |
| `idempotency_key` | yes | 8 to 191 characters, unique per attempt. Send the same key again to retry safely. |
| `reference` | no | Your order or invoice id. It comes back on the payment and on the callback. |
| `callback_url` | no | An `https` URL to POST the result to. Leave it out and poll instead. |
| `currency` | no | Defaults to `KES`. |

### Why a payment failed

| `failure_kind` | What happened |
| --- | --- |
| `customer_declined` | The customer rejected the prompt. |
| `subscriber_cancelled` | The customer cancelled it. |
| `customer_timeout` | They did not enter a PIN in time. |
| `timeout` | M-Pesa did not finish in time. |
| `insufficient_funds` | The phone did not have enough money. |
| `wrong_pin` | The PIN was wrong. |
| `expired` | The prompt window closed before M-Pesa reported a result. |

Other kinds mean the prompt did not complete. Show `failure_message` to the customer and start a new payment with a new `idempotency_key`.

### Errors

| HTTP | `error` | What to do |
| --- | --- | --- |
| 401 | `unauthorized` | The key is missing, wrong, or has been rotated. |
| 409 | `destination_inactive` | Confirm a till, paybill, or bank in Connect first. |
| 422 | `invalid_phone` | Send a Kenyan mobile number. |
| 422 | `invalid_callback_url` | Use an `https` URL, or leave `callback_url` out. |
| 422 | `invalid` | A required field is missing or too short. `idempotency_key` must be at least 8 characters. |
| 422 | `rail_failure` | M-Pesa rejected the prompt before it could be sent. Read `message`. |
| 404 | `not_found` | That payment id is not yours. |

---

## 8. Retrying safely

Use one `idempotency_key` per checkout attempt, for example `order-1042-1`. If your server times out and you are not sure the first call arrived, send the exact same request again and you get the original payment back.

To ask the customer to pay again after a failure, use a new key, such as `order-1042-2`.

---

## 9. Landing it in ViewNinjas

Sketch only — this repo is docs today, so nothing below is compiled or tested. `scope.md` §8 owns the architecture; this is the shape of the code.

### The client

`Viewninjas.Payments.Malipo` sits on Finch, holds no state, and returns tuples. Config carries the URL and the key, so no secret lives in the module.

```elixir
# config/runtime.exs
config :viewninjas, Viewninjas.Payments.Malipo,
  base_url: "https://api.kiosk.ke",
  secret_key: System.fetch_env!("MALIPO_SECRET_KEY")
```

```elixir
defmodule Viewninjas.Payments.Malipo do
  @moduledoc """
  Thin client over Malipo Connect.

  `create/1` pushes an M-Pesa prompt; `get/1` reads a payment's final state.
  Nothing is cached here. The caller owns the idempotency key, and the caller
  decides a payment is paid only when `get/1` returns `:settled`.
  """

  @receive_timeout 15_000
  @ok_statuses [200, 201]

  @type payment :: %{
          id: String.t(),
          status: :pending | :settled | :failed,
          amount: String.t(),
          currency: String.t(),
          receipt: String.t() | nil,
          failure_kind: String.t() | nil,
          failure_message: String.t() | nil
        }

  @doc """
  Create a payment and put the prompt on the customer's phone.

  `attrs`:

    * `:amount` — whole shillings as a decimal string, e.g. `"100.00"`
    * `:customer_phone` — `2547…`
    * `:idempotency_key` — per attempt, e.g. `"order-#{order.id}-1"`
    * `:reference` — optional, our order id, echoed on the callback
    * `:callback_url` — optional, `https`; omit it and poll instead

  A repeated `:idempotency_key` returns the original payment instead of
  prompting again.
  """
  @spec create(map()) :: {:ok, payment()} | {:error, term()}
  def create(attrs) do
    body =
      %{
        amount: attrs.amount,
        customer_phone: attrs.customer_phone,
        idempotency_key: attrs.idempotency_key
      }
      |> put_optional(:reference, attrs[:reference])
      |> put_optional(:callback_url, attrs[:callback_url])
      |> put_optional(:currency, attrs[:currency])

    request(:post, "/v1/payments", Jason.encode!(body))
  end

  @doc "Read a payment. Confirms a callback; this is the source of truth."
  @spec get(String.t()) :: {:ok, payment()} | {:error, term()}
  def get(id), do: request(:get, "/v1/payments/" <> id, nil)

  defp request(method, path, body) do
    headers = [
      {"authorization", "Bearer " <> secret_key()},
      {"content-type", "application/json"}
    ]

    req = Finch.build(method, base_url() <> path, headers, body)

    case Finch.request(req, Viewninjas.Finch, receive_timeout: @receive_timeout) do
      {:ok, %Finch.Response{status: status, body: raw}} when status in @ok_statuses ->
        to_payment(raw)

      {:ok, %Finch.Response{status: status, body: raw}} ->
        {:error, to_error(status, raw)}

      {:error, reason} ->
        {:error, {:transport, reason}}
    end
  end

  defp to_payment(raw) do
    with {:ok, json} <- Jason.decode(raw) do
      {:ok,
       %{
         id: json["id"],
         status: to_status(json["status"]),
         amount: json["amount"],
         currency: json["currency"],
         receipt: json["receipt"],
         failure_kind: json["failure_kind"],
         failure_message: json["failure_message"]
       }}
    end
  end

  defp to_status("pending"), do: :pending
  defp to_status("settled"), do: :settled
  defp to_status("failed"), do: :failed

  # Returns the string code, never a new atom, so a bad payload cannot exhaust the atom table.
  defp to_error(status, raw) do
    case Jason.decode(raw) do
      {:ok, %{"error" => code} = json} -> {:malipo, code, json["message"], status}
      _ -> {:http_error, status}
    end
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp base_url, do: config()[:base_url] || "https://api.kiosk.ke"
  defp secret_key, do: Keyword.fetch!(config(), :secret_key)
  defp config, do: Application.fetch_env!(:viewninjas, __MODULE__)
end
```

### The callback controller

Answers `2xx` immediately. The confirming GET and the ledger write happen in Oban, so a slow callback never makes Malipo retry into a second write.

```elixir
defmodule ViewninjasWeb.MalipoCallbackController do
  use ViewninjasWeb, :controller

  # Malipo retries until it gets a quick 2xx, so answer first and work in Oban.
  def create(conn, params) do
    body = conn.assigns[:raw_body]

    with true <- is_binary(body),
         :ok <- verify(body, get_req_header(conn, "x-malipo-signature")),
         %{"data" => %{"id" => payment_id}} <- params do
      Viewninjas.Workers.ConfirmPayment.enqueue(payment_id)

      send_resp(conn, 200, "")
    else
      _ -> send_resp(conn, 400, "")
    end
  end

  defp verify(body, [header]) do
    secret = Application.fetch_env!(:viewninjas, :malipo_webhook_secret)
    expected = :crypto.mac(:hmac, :sha256, secret, body)
    got = header |> String.replace_prefix("sha256=", "") |> Base.decode16!(case: :mixed)

    if Plug.Crypto.secure_compare(expected, got), do: :ok, else: :error
  end

  defp verify(_body, _headers), do: :error
end
```

Signature checking needs the exact bytes received, so the endpoint that handles the callback must cache the raw body (a small custom body reader, or `Plug.Parsers` with a reader that stashes `raw_body`). Verifying is optional: drop `verify/2` and the confirming GET below still protects the money.

### The confirming job

`ConfirmPayment` is where "paid only when the GET says `settled`" lives — the one place a Malipo result becomes money. It is safe to run for a callback and for a poll; a payment whose row is already terminal is a no-op.

```elixir
defmodule Viewninjas.Workers.ConfirmPayment do
  use Oban.Worker,
    queue: :payments,
    max_attempts: 50,
    # One job per payment: a callback and a poll for the same id coalesce.
    unique: [
      period: 300,
      states: [:available, :scheduled, :executing, :retryable],
      keys: [:payment_id]
    ]

  alias Viewninjas.{Orders, Payments}
  alias Viewninjas.Payments.Malipo

  @poll_interval 3
  @prompt_window 120

  @doc """
  Enqueue (or coalesce into) the confirmation for a payment.

  Safe to call from the callback and from a poller: `unique` makes the second
  caller attach to the first job instead of starting a second one.
  """
  def enqueue(payment_id) do
    new(%{payment_id: payment_id, deadline: System.system_time(:second) + @prompt_window})
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payment_id" => payment_id} = args}) do
    deadline = args["deadline"] || System.system_time(:second) + @prompt_window

    with {:ok, payment} <- Payments.fetch(payment_id) do
      if terminal?(payment.status), do: :ok, else: confirm(payment, deadline)
    else
      {:error, :not_found} -> {:discard, :unknown_payment}
      {:error, reason} -> {:error, reason}
    end
  end

  # Money moves on exactly one signal: Malipo saying settled.
  defp confirm(payment, deadline) do
    case Malipo.get(payment.id) do
      {:ok, %{status: :settled, receipt: receipt}} -> Orders.confirm_paid(payment, receipt)
      {:ok, %{status: :failed} = fresh} -> Payments.mark_failed(payment, fresh)
      {:ok, %{status: :pending}} -> poll_again(deadline)
      {:error, _reason} -> {:error, :malipo_unavailable}
    end
  end

  # Still pending: come back in a few seconds until the prompt window closes.
  # We never fail the payment on our own clock — only Malipo knows the outcome —
  # so past the deadline we stop asking and let the recorded result, or a later
  # reconcile, flip the row. The order stays retryable meanwhile.
  defp poll_again(deadline) do
    if System.system_time(:second) < deadline do
      {:snooze, @poll_interval}
    else
      {:cancel, :prompt_window_elapsed}
    end
  end

  defp terminal?(:settled), do: true
  defp terminal?(:failed), do: true
  defp terminal?(_), do: false
end
```

The job polls instead of blocking: one `GET` per run, then `{:snooze, 3}` while the payment is still `pending`, until the deadline in `args` passes. `Orders.confirm_paid/2` writes the ledger entry and enqueues placement in one transaction. Two rules hold it together:

- **Settled is the only way money moves.** A transport error retries with backoff; it never guesses.
- **We never fail a payment on our own clock.** Past the deadline the job cancels without deciding, because Malipo's own `expired`/`timeout` result, delivered by the callback or a later reconcile, is authoritative. Until then the order simply stays `awaiting_payment`.

The `unique` option is what lets the callback and a poller both call `enqueue/1` for the same payment: the second insert is dropped while a job for that `payment_id` is available, scheduled, executing, or retrying. Keep `max_attempts` comfortably above the number of polls in the window.

---

### The sweep

The callback can be lost and a request can die mid-poll, so a cron job re-enqueues confirmation for anything still `pending` past the prompt window. It is the "later reconcile" the worker comments refer to.

```elixir
# config/config.exs
config :viewninjas, Oban,
  repo: Viewninjas.Repo,
  queues: [payments: 10, default: 10],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [{"* * * * *", Viewninjas.Workers.SweepPendingPayments}]}
  ]
```

```elixir
defmodule Viewninjas.Workers.SweepPendingPayments do
  @moduledoc """
  Backstop for a dropped callback or a dead poll.

  Every minute, re-enqueue `ConfirmPayment` for payments still `pending` past
  the prompt window. `unique` drops the work when a confirmation is already in
  flight, so this is cheap and never prompts twice.
  """

  use Oban.Worker, queue: :payments, max_attempts: 3

  alias Viewninjas.Payments
  alias Viewninjas.Workers.ConfirmPayment

  @stale_after 90      # the prompt window; past this, M-Pesa is done
  @give_up_after 3_600 # past an hour, stop probing and surface to a human

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()
    from = DateTime.add(now, -@give_up_after, :second)
    to = DateTime.add(now, -@stale_after, :second)

    for payment <- Payments.list_pending_between(from, to, limit: 500) do
      ConfirmPayment.enqueue(payment.id)
    end

    :ok
  end
end
```

```elixir
# Viewninjas.Payments
def list_pending_between(from, to, opts \\ []) do
  limit = Keyword.get(opts, :limit, 500)

  from(p in Payment,
    where: p.status == :pending and p.inserted_at >= ^from and p.inserted_at < ^to,
    order_by: [asc: p.inserted_at],
    limit: ^limit
  )
  |> Repo.all()
end
```

The upper bound is what keeps this honest. Without `@give_up_after`, a payment Malipo never resolves would be re-probed forever. Past an hour the row is a job for a human, not for the poller — the same "an unknown state is first-class" rule the supplier boundary uses in `scope.md` §5. Between the two bounds, `unique` throttles the sweep to at most one probe per payment per five minutes.

---

## 10. Reconciling a settlement statement

**An assumption to confirm first.** Nothing in the request/response API above carries the fee, and none of it shows a payment we never heard about. This sketch assumes Malipo hands you a **statement** per settlement — a CSV or an endpoint — with one line per transaction: the Malipo id, the M-Pesa receipt, gross, fee, net, and the settlement date, plus a payout total. Confirm the format with Malipo before writing a parser; everything below is the shape, not a confirmed feed.

`payments` knows the gross and that a payment is `settled`. It does not know what the money cost to collect, and it cannot see a payment the callback missed and the sweep gave up on. The statement is the only outside view of both, and `scope.md` §11's profit panel is wrong without the fee.

### The shape

1. **Land the statement raw.** `settlement_lines`, append-only, one row per line, carrying the statement's own id and period. A re-import of the same statement is a no-op, keyed on `(statement_id, provider_ref)`.
2. **Match.** Find our payment by `malipo_payment_id`, falling back to the M-Pesa `receipt`, matched **inside the statement's window** — never globally, so a receipt reused years apart cannot collide.
3. **Classify.** Every line lands in one of four buckets:

   | Bucket | Meaning |
   | --- | --- |
   | `matched` | one line, one payment, gross agrees |
   | `amount_mismatch` | found, but the gross differs |
   | `provider_only` | the statement has a settled payment we have no row for |
   | `local_only` | we believe it settled, and the statement has no line |

4. **Apply, carefully.** On `matched`, write `fee_cents` and `settled_on` onto the payment. **Nothing else is automatic.** `provider_only` and `local_only` are flags for a person, never an automatic ledger write — §8's rule holds: only a confirming `GET` settles a payment, and a statement line is not a `GET`.
5. **Report the payout.** `sum(net_cents)` across the statement against what the till or bank actually received. That difference is the one number that cannot be argued with.

```elixir
# one statement, one pass
lines
|> Enum.map(&classify/1)
|> Enum.group_by(& &1.kind)
```

```elixir
defp classify(%Line{provider_ref: ref, receipt: receipt, gross_cents: gross} = line) do
  case Payments.find_settled(ref: ref, receipt: receipt, window: line.window) do
    nil -> %{line | kind: :provider_only}
    %Payment{amount_cents: ^gross} = p -> %{line | kind: :matched, payment: p}
    %Payment{} = p -> %{line | kind: :amount_mismatch, payment: p}
  end
end
```

```elixir
# the reverse pass: payments we settled that the statement never mentions
Payments.settled_in(window)
|> Enum.reject(&MapSet.member?(statement_refs, &1.malipo_payment_id))
|> Enum.each(&flag_local_only/1)
```

`Payments.find_settled/1`, `flag_local_only/1`, and `Line` are illustrative — the sketch shows the shape, not a module.

### The traps

- **Settlement day is not the sale day.** M-Pesa settles on the next business day, so a Friday-evening payment lands on Monday. The window must be the statement's period plus a business-day margin, or every weekend lights up as `local_only`.
- **Fees are tiered, not a rate.** Do not fit a percentage and multiply. Store the real fee per line; compute the effective rate per day only to watch it drift.
- **A re-import must be free.** Idempotency on `(statement_id, provider_ref)`, or a retry doubles the fee total and makes profit look worse than it is.
- **`local_only` is a queue, not an accusation.** It is usually the cut-off, or a refund already reversed. Investigate; do not auto-reverse.
- **Never un-settle to make the numbers agree.** If a statement contradicts a `settled` payment, a person resolves it. The ledger only ever gets a new, opposite entry (`scope.md` §6).

Run it as a daily job once the statement for the prior settlement day lands, and give the super-admin the four buckets and the payout delta on one screen. Ultimately the whole point is the gap between "we think we earned KSh X" and "we received KSh X", and only the bank sees the second number.

---

See `scope.md` §8 for how this fits the app — statuses, ledger, and the placement rule.
