defmodule Monzo.Transactions do
  @moduledoc """
  The Transactions resource: retrieving, listing (with lazy pagination),
  and annotating transactions.
  """

  alias Monzo.Client
  alias Monzo.Error.ValidationError
  alias Monzo.HTTP
  alias Monzo.Internal.Path
  alias Monzo.Pagination
  alias Monzo.Transaction

  @type expand_field :: :merchant

  @type retrieve_params :: %{
          required(:transaction_id) => String.t(),
          optional(:expand) => [expand_field()]
        }

  @doc """
  Fetches a single transaction by id, optionally expanding `:merchant` inline.

      {:ok, tx} = Monzo.Transactions.retrieve(client, %{transaction_id: "tx_123", expand: [:merchant]})
  """
  @spec retrieve(Client.t(), retrieve_params()) ::
          {:ok, Transaction.t()} | {:error, Exception.t()}
  def retrieve(%Client{} = client, %{transaction_id: transaction_id} = params)
      when is_binary(transaction_id) and transaction_id != "" do
    query = %{"expand[]" => expand_param(params[:expand])}
    path = "/transactions/#{Path.encode_segment(transaction_id)}"

    with {:ok, %{"transaction" => json}} <-
           HTTP.request(client, method: :get, path: path, query: query) do
      {:ok, Transaction.from_json(json)}
    end
  end

  def retrieve(%Client{}, _params) do
    {:error, %ValidationError{field: :transaction_id, message: "must not be empty"}}
  end

  @type list_params :: %{
          required(:account_id) => String.t(),
          optional(:since) => String.t(),
          optional(:before) => String.t(),
          optional(:limit) => pos_integer(),
          optional(:expand) => [expand_field()]
        }

  @doc """
  Returns a single page of transactions for an account.

  > #### Full-history sync window {: .warning}
  >
  > Monzo only allows fetching a user's complete transaction history during
  > the first 5 minutes after authentication. After that window, only the
  > last 90 days are available. If you need full history, call `list/2` or
  > `stream/2` immediately after the OAuth callback completes.
  """
  @spec list(Client.t(), list_params()) ::
          {:ok, [Transaction.t()]} | {:error, Exception.t()}
  def list(%Client{} = client, %{account_id: account_id} = params)
      when is_binary(account_id) and account_id != "" do
    query = %{
      "account_id" => account_id,
      "since" => params[:since],
      "before" => params[:before],
      "limit" => params[:limit],
      "expand[]" => expand_param(params[:expand])
    }

    with {:ok, %{"transactions" => transactions}} <-
           HTTP.request(client, method: :get, path: "/transactions", query: query) do
      {:ok, Enum.map(transactions, &Transaction.from_json/1)}
    end
  end

  def list(%Client{}, _params) do
    {:error, %ValidationError{field: :account_id, message: "must not be empty"}}
  end

  @type stream_params :: %{
          required(:account_id) => String.t(),
          optional(:before) => String.t(),
          optional(:expand) => [expand_field()],
          optional(:since) => String.t(),
          optional(:page_size) => pos_integer()
        }

  @doc """
  Returns a lazy `Stream` that walks every transaction for an account,
  oldest first, across as many pages as needed - fetching each page only
  as the stream is consumed.

      client
      |> Monzo.Transactions.stream(%{account_id: account_id})
      |> Enum.each(fn tx -> IO.puts("\#{tx.created} \#{tx.amount} \#{tx.description}") end)

      # Or lazily take just the first 10:
      first_ten = client |> Monzo.Transactions.stream(%{account_id: account_id}) |> Enum.take(10)
  """
  @spec stream(Client.t(), stream_params()) :: Enumerable.t()
  def stream(%Client{} = client, params) do
    fetch_page = fn since, limit ->
      list(client, %{
        account_id: params.account_id,
        since: since || params[:since],
        before: params[:before],
        expand: params[:expand],
        limit: limit
      })
    end

    Pagination.stream(fetch_page, &Transaction.cursor_value/1,
      page_size: Map.get(params, :page_size, 100),
      since: params[:since]
    )
  end

  @type annotate_params :: %{
          required(:transaction_id) => String.t(),
          required(:metadata) => %{optional(String.t()) => String.t()}
        }

  @doc """
  Sets or deletes key/value metadata on a transaction. Set a value to an
  empty string to delete that key. Setting the reserved `"notes"` key
  updates the transaction's top-level `notes` field instead.
  """
  @spec annotate(Client.t(), annotate_params()) ::
          {:ok, Transaction.t()} | {:error, Exception.t()}
  def annotate(%Client{} = client, %{transaction_id: transaction_id, metadata: metadata})
      when is_binary(transaction_id) and transaction_id != "" do
    form = Map.new(metadata, fn {k, v} -> {"metadata[#{k}]", v} end)
    path = "/transactions/#{Path.encode_segment(transaction_id)}"

    with {:ok, %{"transaction" => json}} <-
           HTTP.request(client, method: :patch, path: path, encoding: :form, form: form) do
      {:ok, Transaction.from_json(json)}
    end
  end

  def annotate(%Client{}, _params) do
    {:error, %ValidationError{field: :transaction_id, message: "must not be empty"}}
  end

  defp expand_param(nil), do: nil
  defp expand_param(fields), do: Enum.map(fields, &Atom.to_string/1)
end
