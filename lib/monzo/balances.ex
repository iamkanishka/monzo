defmodule Monzo.Balances do
  @moduledoc "The Balance resource: reading an account's current balance."

  alias Monzo.Balance
  alias Monzo.Client
  alias Monzo.Error.ValidationError
  alias Monzo.HTTP

  @doc """
  Returns balance information for a specific account.

      {:ok, balance} = Monzo.Balances.read(client, account_id)
  """
  @spec read(Client.t(), String.t()) :: {:ok, Balance.t()} | {:error, Exception.t()}
  def read(%Client{} = client, account_id) when is_binary(account_id) and account_id != "" do
    with {:ok, json} <-
           HTTP.request(client,
             method: :get,
             path: "/balance",
             query: %{"account_id" => account_id}
           ) do
      {:ok, Balance.from_json(json)}
    end
  end

  def read(%Client{}, _account_id) do
    {:error, %ValidationError{field: :account_id, message: "must not be empty"}}
  end
end
