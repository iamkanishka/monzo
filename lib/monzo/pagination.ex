defmodule Monzo.Pagination do
  @moduledoc """
  Generic, lazy pagination built on `Stream.resource/3` for Monzo list
  endpoints that are ordered oldest-first and support a `since` cursor
  plus a page `limit`.
  """

  @doc """
  Builds a lazy `Stream` that walks every page of a paginated endpoint,
  yielding individual items.

  `fetch_page` is called with `since` (a cursor string or `nil`) and
  `limit`, and must return `{:ok, items}` or `{:error, reason}`. The last
  item's `cursor_fun.(item)` becomes the next page's `since` value. A page
  shorter than `limit` (or empty) ends the stream.

  If `fetch_page` returns an error, the stream halts and raises that
  error via `Stream.resource/3`'s natural propagation - wrap consumption
  in `try/rescue` or use `Enum.reduce_while/3` if you need to handle
  paging errors without an exception. Most callers will simply use
  `Enum.to_list/1`, `Enum.take/2`, or a `for` comprehension.

  ## Example

      fetch_page = fn since, limit ->
        Monzo.Transactions.list(client, %{account_id: account_id, since: since, limit: limit})
      end

      Monzo.Pagination.stream(fetch_page, &Monzo.Transaction.cursor_value/1, page_size: 100)
      |> Enum.each(fn tx -> IO.inspect(tx.id) end)
  """
  @spec stream(
          (String.t() | nil, pos_integer() -> {:ok, [item]} | {:error, term()}),
          (item -> String.t() | nil),
          keyword()
        ) :: Enumerable.t()
        when item: term()
  def stream(fetch_page, cursor_fun, opts \\ []) do
    page_size = Keyword.get(opts, :page_size, 100)
    since = Keyword.get(opts, :since)

    Stream.resource(
      fn -> {:continue, since} end,
      &next_page(&1, fetch_page, cursor_fun, page_size),
      fn _acc -> :ok end
    )
  end

  defp next_page(:done, _fetch_page, _cursor_fun, _page_size) do
    {:halt, :done}
  end

  defp next_page({:continue, since}, fetch_page, cursor_fun, page_size) do
    case fetch_page.(since, page_size) do
      {:ok, []} ->
        {:halt, :done}

      {:ok, items} ->
        {items, next_state(items, cursor_fun, page_size)}

      {:error, reason} ->
        raise "Monzo pagination fetch failed: #{inspect(reason)}"
    end
  end

  defp next_state(items, cursor_fun, page_size) do
    next_since = cursor_fun.(List.last(items))

    case length(items) do
      count when count < page_size -> :done
      _ -> {:continue, next_since}
    end
  end
end
