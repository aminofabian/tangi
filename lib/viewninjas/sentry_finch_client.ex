defmodule ViewNinjas.SentryFinchClient do
  @moduledoc """
  Sends Sentry events over the app's shared Finch pool.

  Sentry defaults to Hackney, but ViewNinjas keeps a single HTTP client
  (`ViewNinjas.Finch`) for every outbound call, so this implements
  `Sentry.HTTPClient` on top of that pool instead of pulling in a second
  client. We deliberately do not implement `child_spec/0`: Finch is already
  supervised by `ViewNinjas.Application`, so Sentry has nothing to start.
  """
  @behaviour Sentry.HTTPClient

  @impl true
  def post(url, headers, body) do
    case Finch.request(Finch.build(:post, url, headers, body), ViewNinjas.Finch) do
      {:ok, %Finch.Response{status: status, headers: response_headers, body: response_body}} ->
        {:ok, status, response_headers, response_body}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
