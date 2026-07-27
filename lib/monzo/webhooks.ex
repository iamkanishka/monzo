defmodule Monzo.Webhooks do
  @moduledoc """
  The Webhooks resource: registering callback URLs, and parsing/validating
  inbound event deliveries.
  """

  alias Monzo.Client
  alias Monzo.Error.{ValidationError, WebhookVerificationError}
  alias Monzo.HTTP
  alias Monzo.Internal.Path
  alias Monzo.JSON
  alias Monzo.Transaction
  alias Monzo.Webhook

  @doc """
  Registers a URL to receive real-time events for an account. Monzo will
  POST to this URL on matching events, retrying up to 5 times with
  exponential backoff if your endpoint fails to respond successfully.
  """
  @spec register(Client.t(), String.t(), String.t()) ::
          {:ok, Webhook.t()} | {:error, Exception.t()}
  def register(%Client{} = client, account_id, url)
      when is_binary(account_id) and account_id != "" and is_binary(url) and url != "" do
    form = %{"account_id" => account_id, "url" => url}

    request =
      HTTP.request(client,
        method: :post,
        path: "/webhooks",
        encoding: :form,
        form: form,
        idempotent: false
      )

    with {:ok, %{"webhook" => json}} <- request, do: {:ok, Webhook.from_json(json)}
  end

  def register(%Client{}, _account_id, _url) do
    {:error,
     %ValidationError{field: :account_id, message: "account_id and url must not be empty"}}
  end

  @doc "Lists the webhooks registered for an account."
  @spec list(Client.t(), String.t()) :: {:ok, [Webhook.t()]} | {:error, Exception.t()}
  def list(%Client{} = client, account_id) when is_binary(account_id) and account_id != "" do
    request =
      HTTP.request(client,
        method: :get,
        path: "/webhooks",
        query: %{"account_id" => account_id}
      )

    with {:ok, %{"webhooks" => webhooks}} <- request do
      {:ok, Enum.map(webhooks, &Webhook.from_json/1)}
    end
  end

  def list(%Client{}, _account_id) do
    {:error, %ValidationError{field: :account_id, message: "must not be empty"}}
  end

  @doc "Deletes a registered webhook. Monzo will stop sending notifications to it."
  @spec delete(Client.t(), String.t()) :: :ok | {:error, Exception.t()}
  def delete(%Client{} = client, webhook_id) when is_binary(webhook_id) and webhook_id != "" do
    path = "/webhooks/#{Path.encode_segment(webhook_id)}"

    case HTTP.request(client, method: :delete, path: path) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  def delete(%Client{}, _webhook_id) do
    {:error, %ValidationError{field: :webhook_id, message: "must not be empty"}}
  end

  @doc """
  Parses and minimally validates a raw incoming webhook request body into
  a `Webhook.Event`.

  > #### Webhook security {: .warning}
  >
  > As of this writing, Monzo does not document a cryptographic signature
  > (e.g. HMAC) on webhook deliveries, so this function cannot and does not
  > perform signature verification. To defend your endpoint:
  >
  >   * Serve it over HTTPS only.
  >   * Treat the registered URL as a secret (use an unguessable path segment).
  >   * Validate the event's `account_id` against the accounts you expect
  >     using `assert_expected_account/2` before trusting the payload.
  >   * Re-fetch the transaction via `Monzo.Transactions.retrieve/2` before
  >     acting on financially sensitive data, rather than trusting the
  >     webhook body alone.
  """
  @spec parse_event(String.t()) ::
          {:ok, Webhook.Event.t()} | {:error, WebhookVerificationError.t()}
  def parse_event(raw_body) when is_binary(raw_body) do
    with {:ok, decoded} <- decode_json(raw_body),
         {:ok, decoded} <- ensure_map(decoded),
         {:ok, type} <- require_field(decoded, "type"),
         {:ok, data} <- require_field(decoded, "data") do
      {:ok, %Webhook.Event{type: type, data: Transaction.from_json(data)}}
    end
  end

  defp decode_json(raw_body) do
    case JSON.decode(raw_body) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, reason} ->
        {:error, %WebhookVerificationError{message: "body is not valid JSON: #{inspect(reason)}"}}
    end
  end

  defp ensure_map(decoded) when is_map(decoded), do: {:ok, decoded}

  defp ensure_map(_decoded),
    do: {:error, %WebhookVerificationError{message: "body is not a JSON object"}}

  defp require_field(map, key) do
    case Map.get(map, key) do
      nil -> {:error, %WebhookVerificationError{message: "missing #{inspect(key)} field"}}
      value -> {:ok, value}
    end
  end

  @doc """
  Returns `{:error, %Monzo.Error.WebhookVerificationError{}}` if the
  event's transaction `account_id` is not present in
  `expected_account_ids`, `:ok` otherwise.
  """
  @spec assert_expected_account(Webhook.Event.t(), [String.t()]) ::
          :ok | {:error, WebhookVerificationError.t()}
  def assert_expected_account(
        %Webhook.Event{data: %{account_id: account_id}},
        expected_account_ids
      ) do
    if account_id in expected_account_ids do
      :ok
    else
      {:error,
       %WebhookVerificationError{
         message: "account_id #{inspect(account_id)} is not in the list of expected accounts"
       }}
    end
  end
end
