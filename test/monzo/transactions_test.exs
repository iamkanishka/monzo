defmodule Monzo.TransactionsTest do
  use ExUnit.Case, async: true

  alias Monzo.Test.MockAdapter

  defp client(agent) do
    Monzo.Client.new(
      base_url: "https://api.monzo.com",
      adapter: MockAdapter.adapter(agent),
      access_token: "t"
    )
  end

  defp tx_json(id, created) do
    %{
      "id" => id,
      "amount" => -100,
      "created" => created,
      "currency" => "GBP",
      "description" => "Coffee",
      "merchant" => "merch_1",
      "metadata" => %{},
      "notes" => "",
      "is_load" => false,
      "settled" => created,
      "category" => "eating_out"
    }
  end

  test "retrieve/2 fetches a single transaction with expand" do
    {:ok, agent} =
      MockAdapter.start_link([
        MockAdapter.json_response(%{
          "transaction" =>
            Map.put(tx_json("tx_1", "2020-01-01T00:00:00Z"), "merchant", %{
              "id" => "merch_1",
              "name" => "Cafe"
            })
        })
      ])

    assert {:ok, tx} =
             Monzo.Transactions.retrieve(client(agent), %{
               transaction_id: "tx_1",
               expand: [:merchant]
             })

    assert tx.id == "tx_1"
    assert tx.merchant.name == "Cafe"

    [req] = MockAdapter.requests(agent)
    assert req.url == "https://api.monzo.com/transactions/tx_1?expand%5B%5D=merchant"
  end

  test "list/2 returns a page of transactions" do
    {:ok, agent} =
      MockAdapter.start_link([
        MockAdapter.json_response(%{"transactions" => [tx_json("tx_1", "2020-01-01T00:00:00Z")]})
      ])

    assert {:ok, [tx]} = Monzo.Transactions.list(client(agent), %{account_id: "acc_1"})
    assert tx.merchant_id == "merch_1"
  end

  test "list/2 rejects an empty account_id" do
    {:ok, agent} = MockAdapter.start_link([])

    assert {:error, %Monzo.Error.ValidationError{}} =
             Monzo.Transactions.list(client(agent), %{account_id: ""})
  end

  test "annotate/2 sets and clears metadata" do
    {:ok, agent} =
      MockAdapter.start_link([
        MockAdapter.json_response(%{
          "transaction" =>
            Map.put(tx_json("tx_1", "2020-01-01T00:00:00Z"), "metadata", %{"foo" => "bar"})
        })
      ])

    assert {:ok, tx} =
             Monzo.Transactions.annotate(client(agent), %{
               transaction_id: "tx_1",
               metadata: %{"foo" => "bar", "old_key" => ""}
             })

    assert tx.metadata == %{"foo" => "bar"}

    [req] = MockAdapter.requests(agent)
    assert req.method == :patch
    decoded = URI.decode_query(req.body)
    assert decoded["metadata[foo]"] == "bar"
    assert decoded["metadata[old_key]"] == ""
  end

  test "stream/2 walks every page until a short page ends the stream" do
    page1 = [tx_json("tx_1", "2020-01-01T00:00:00Z"), tx_json("tx_2", "2020-01-02T00:00:00Z")]
    page2 = [tx_json("tx_3", "2020-01-03T00:00:00Z")]

    {:ok, agent} =
      MockAdapter.start_link([
        MockAdapter.json_response(%{"transactions" => page1}),
        MockAdapter.json_response(%{"transactions" => page2})
      ])

    ids =
      client(agent)
      |> Monzo.Transactions.stream(%{account_id: "acc_1", page_size: 2})
      |> Enum.map(& &1.id)

    assert ids == ["tx_1", "tx_2", "tx_3"]
    assert MockAdapter.call_count(agent) == 2

    [_first, second] = MockAdapter.requests(agent)
    assert second.url =~ "since=2020-01-02T00%3A00%3A00Z"
  end

  test "stream/2 stops immediately when the first page is empty" do
    {:ok, agent} = MockAdapter.start_link([MockAdapter.json_response(%{"transactions" => []})])

    result = client(agent) |> Monzo.Transactions.stream(%{account_id: "acc_1"}) |> Enum.to_list()

    assert result == []
    assert MockAdapter.call_count(agent) == 1
  end

  test "stream/2 is lazy and only fetches as many pages as consumed" do
    page1 = [tx_json("tx_1", "2020-01-01T00:00:00Z")]
    page2 = [tx_json("tx_2", "2020-01-02T00:00:00Z")]

    {:ok, agent} =
      MockAdapter.start_link([
        MockAdapter.json_response(%{"transactions" => page1}),
        MockAdapter.json_response(%{"transactions" => page2})
      ])

    [first] =
      client(agent)
      |> Monzo.Transactions.stream(%{account_id: "acc_1", page_size: 1})
      |> Enum.take(1)

    assert first.id == "tx_1"
    assert MockAdapter.call_count(agent) == 1
  end
end
