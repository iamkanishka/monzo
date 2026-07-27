defmodule Monzo.Receipts do
  @moduledoc """
  The Transaction Receipts resource. Unlike every other Monzo resource,
  this endpoint is JSON-bodied rather than form-encoded.
  """

  alias Monzo.Client
  alias Monzo.Error.ValidationError
  alias Monzo.HTTP
  alias Monzo.Receipt

  @doc """
  Creates or updates a receipt for a transaction. `external_id` acts as an
  idempotency key: calling this again with the same `external_id` updates
  the existing receipt.
  """
  @spec create(Client.t(), Receipt.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def create(
        %Client{} = client,
        %Receipt{external_id: external_id, transaction_id: transaction_id, items: items} = receipt
      ) do
    with :ok <- validate_present(:external_id, external_id),
         :ok <- validate_present(:transaction_id, transaction_id),
         :ok <- validate_non_empty_list(:items, items) do
      request =
        HTTP.request(client,
          method: :put,
          path: "/transaction-receipts",
          encoding: :json,
          json: Receipt.to_json(receipt)
        )

      with {:ok, json} <- request, do: {:ok, json["receipt_id"]}
    end
  end

  @doc "Reads back a receipt you created, by its `external_id`. You can only read your own receipts."
  @spec retrieve(Client.t(), String.t()) :: {:ok, Receipt.t()} | {:error, Exception.t()}
  def retrieve(%Client{} = client, external_id)
      when is_binary(external_id) and external_id != "" do
    request =
      HTTP.request(client,
        method: :get,
        path: "/transaction-receipts",
        query: %{"external_id" => external_id}
      )

    with {:ok, %{"receipt" => json}} <- request do
      {:ok, Receipt.from_json(json)}
    end
  end

  def retrieve(%Client{}, _external_id) do
    {:error, %ValidationError{field: :external_id, message: "must not be empty"}}
  end

  @doc "Deletes a receipt by its `external_id`."
  @spec delete(Client.t(), String.t()) :: :ok | {:error, Exception.t()}
  def delete(%Client{} = client, external_id) when is_binary(external_id) and external_id != "" do
    case HTTP.request(client,
           method: :delete,
           path: "/transaction-receipts",
           query: %{"external_id" => external_id}
         ) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  def delete(%Client{}, _external_id) do
    {:error, %ValidationError{field: :external_id, message: "must not be empty"}}
  end

  defp validate_present(_field, value) when is_binary(value) and value != "", do: :ok

  defp validate_present(field, _value),
    do: {:error, %ValidationError{field: field, message: "must not be empty"}}

  defp validate_non_empty_list(_field, list) when is_list(list) and list != [], do: :ok

  defp validate_non_empty_list(field, _list),
    do: {:error, %ValidationError{field: field, message: "must contain at least one item"}}
end
