defmodule Monzo.Pots do
  @moduledoc "The Pots resource: listing pots and moving money into/out of them."

  alias Monzo.Client
  alias Monzo.Error.ValidationError
  alias Monzo.HTTP
  alias Monzo.Internal.Path
  alias Monzo.Pot

  @type transfer_params :: %{
          required(:pot_id) => String.t(),
          required(:amount) => integer(),
          required(:dedupe_id) => String.t()
        }

  @doc """
  Returns a list of pots owned by the currently authorised user for the
  given current account.
  """
  @spec list(Client.t(), String.t()) :: {:ok, [Pot.t()]} | {:error, Exception.t()}
  def list(%Client{} = client, current_account_id) do
    request =
      HTTP.request(client,
        method: :get,
        path: "/pots",
        query: %{"current_account_id" => current_account_id}
      )

    with {:ok, %{"pots" => pots}} <- request do
      {:ok, Enum.map(pots, &Pot.from_json/1)}
    end
  end

  @doc """
  Moves money from an account into a pot.

  `:dedupe_id` must remain static across retries of the *same* logical
  deposit to prevent Monzo from double-processing it; generate a new one
  for each new deposit.
  """
  @spec deposit(Client.t(), transfer_params() | %{source_account_id: String.t()}) ::
          {:ok, Pot.t()} | {:error, Exception.t()}
  def deposit(%Client{} = client, %{
        pot_id: pot_id,
        amount: amount,
        dedupe_id: dedupe_id,
        source_account_id: source_account_id
      }) do
    with :ok <- validate_transfer(pot_id, amount, dedupe_id),
         :ok <- validate_present(:source_account_id, source_account_id) do
      request =
        HTTP.request(client,
          method: :put,
          path: "/pots/#{Path.encode_segment(pot_id)}/deposit",
          encoding: :form,
          form: %{
            "source_account_id" => source_account_id,
            "amount" => amount,
            "dedupe_id" => dedupe_id
          }
        )

      with {:ok, json} <- request, do: {:ok, Pot.from_json(json)}
    end
  end

  @doc """
  Moves money from a pot into an account.

  `:dedupe_id` must remain static across retries of the *same* logical
  withdrawal to prevent Monzo from double-processing it.
  """
  @spec withdraw(Client.t(), transfer_params() | %{destination_account_id: String.t()}) ::
          {:ok, Pot.t()} | {:error, Exception.t()}
  def withdraw(%Client{} = client, %{
        pot_id: pot_id,
        amount: amount,
        dedupe_id: dedupe_id,
        destination_account_id: destination_account_id
      }) do
    with :ok <- validate_transfer(pot_id, amount, dedupe_id),
         :ok <- validate_present(:destination_account_id, destination_account_id) do
      request =
        HTTP.request(client,
          method: :put,
          path: "/pots/#{Path.encode_segment(pot_id)}/withdraw",
          encoding: :form,
          form: %{
            "destination_account_id" => destination_account_id,
            "amount" => amount,
            "dedupe_id" => dedupe_id
          }
        )

      with {:ok, json} <- request, do: {:ok, Pot.from_json(json)}
    end
  end

  defp validate_transfer(pot_id, amount, dedupe_id) do
    with :ok <- validate_present(:pot_id, pot_id),
         :ok <- validate_positive_integer(:amount, amount) do
      validate_present(:dedupe_id, dedupe_id)
    end
  end

  defp validate_present(_field, value) when is_binary(value) and value != "", do: :ok

  defp validate_present(field, _value),
    do: {:error, %ValidationError{field: field, message: "must not be empty"}}

  defp validate_positive_integer(_field, value) when is_integer(value) and value > 0, do: :ok

  defp validate_positive_integer(field, _value) do
    {:error,
     %ValidationError{field: field, message: "must be a positive integer number of minor units"}}
  end
end
