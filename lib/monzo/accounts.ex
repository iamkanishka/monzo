defmodule Monzo.Accounts do
  @moduledoc "The Accounts resource: listing the user's Monzo current accounts."

  alias Monzo.Client

  @type list_params :: %{optional(:type) => :uk_retail | :uk_retail_joint}

  @doc """
  Returns a list of accounts owned by the currently authorised user.

      {:ok, accounts} = Monzo.Accounts.list(client)
      {:ok, joint_accounts} = Monzo.Accounts.list(client, %{type: :uk_retail_joint})
  """
  @spec list(Client.t(), list_params()) :: {:ok, [Monzo.Account.t()]} | {:error, Exception.t()}
  def list(%Client{} = client, params \\ %{}) do
    query = %{"account_type" => account_type_param(params[:type])}

    with {:ok, %{"accounts" => accounts}} <-
           Monzo.HTTP.request(client, method: :get, path: "/accounts", query: query) do
      {:ok, Enum.map(accounts, &Monzo.Account.from_json/1)}
    end
  end

  defp account_type_param(nil), do: nil
  defp account_type_param(:uk_retail), do: "uk_retail"
  defp account_type_param(:uk_retail_joint), do: "uk_retail_joint"
end
