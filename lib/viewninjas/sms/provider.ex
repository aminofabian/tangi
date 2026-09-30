defmodule ViewNinjas.Sms.Provider do
  @moduledoc """
  The SMS provider boundary. The app talks to `ViewNinjas.Sms`, which selects
  the configured implementation; adding a provider is a module plus a config
  line, not a change to the call sites.
  """

  @typedoc """
  What a provider reports back for an accepted message.

    * `provider_ref` — the provider's id, used to match delivery reports.
    * `status` — one of `:queued`, `:sent`, `:delivered`, `:failed`.
    * `cost_micros` — the cost in micros of KES, when the provider reports it.
  """
  @type result :: %{
          provider_ref: String.t() | nil,
          status: atom(),
          cost_micros: non_neg_integer() | nil
        }

  @doc "Sends one SMS. Returns the reference, status and cost, or an error."
  @callback send_sms(to :: String.t(), body :: String.t()) ::
              {:ok, result()} | {:error, term()}
end
