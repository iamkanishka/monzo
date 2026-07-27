defmodule Monzo.ReceiptsTest do
  use ExUnit.Case, async: true

  alias Monzo.Receipt
  alias Monzo.Test.MockAdapter

  defp client(agent) do
    Monzo.Client.new(
      base_url: "https://api.monzo.com",
      adapter: MockAdapter.adapter(agent),
      access_token: "t"
    )
  end

  defp sample_receipt do
    %Receipt{
      external_id: "order-1",
      transaction_id: "tx_1",
      total: 1299,
      currency: "GBP",
      items: [%Receipt.Item{description: "Burger", quantity: 1, amount: 1299, currency: "GBP"}]
    }
  end

  test "create/2 sends a JSON body via PUT" do
    {:ok, agent} =
      MockAdapter.start_link([MockAdapter.json_response(%{"receipt_id" => "receipt_1"})])

    assert {:ok, "receipt_1"} = Monzo.Receipts.create(client(agent), sample_receipt())

    [req] = MockAdapter.requests(agent)
    assert req.method == :put
    assert {"content-type", "application/json"} in req.headers
    assert {:ok, decoded} = Monzo.JSON.decode(req.body)
    assert decoded["external_id"] == "order-1"

    assert decoded["items"] == [
             %{
               "description" => "Burger",
               "quantity" => 1,
               "unit" => nil,
               "amount" => 1299,
               "currency" => "GBP",
               "tax" => nil,
               "sub_items" => []
             }
           ]
  end

  test "create/2 rejects a receipt with no items" do
    {:ok, agent} = MockAdapter.start_link([])
    receipt = %{sample_receipt() | items: []}

    assert {:error, %Monzo.Error.ValidationError{field: :items}} =
             Monzo.Receipts.create(client(agent), receipt)
  end

  test "retrieve/2 fetches a receipt by external_id" do
    {:ok, agent} =
      MockAdapter.start_link([
        MockAdapter.json_response(%{
          "receipt" => %{
            "external_id" => "order-1",
            "transaction_id" => "tx_1",
            "total" => 1299,
            "currency" => "GBP",
            "items" => []
          }
        })
      ])

    assert {:ok, receipt} = Monzo.Receipts.retrieve(client(agent), "order-1")
    assert receipt.external_id == "order-1"

    [req] = MockAdapter.requests(agent)
    assert req.url == "https://api.monzo.com/transaction-receipts?external_id=order-1"
  end

  test "delete/2 deletes a receipt" do
    {:ok, agent} = MockAdapter.start_link([MockAdapter.empty_response()])
    assert :ok = Monzo.Receipts.delete(client(agent), "order-1")

    [req] = MockAdapter.requests(agent)
    assert req.method == :delete
  end
end
