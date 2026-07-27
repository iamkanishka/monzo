defmodule Monzo.TransactionTest do
  use ExUnit.Case, async: true

  alias Monzo.Transaction

  test "from_json/1 with an unexpanded (string) merchant" do
    json = %{
      "id" => "tx_1",
      "amount" => -100,
      "created" => "2020-01-01T00:00:00Z",
      "currency" => "GBP",
      "description" => "Coffee",
      "metadata" => %{},
      "notes" => "",
      "is_load" => false,
      "settled" => "",
      "merchant" => "merch_1"
    }

    tx = Transaction.from_json(json)

    assert tx.merchant_id == "merch_1"
    assert tx.merchant == nil
    assert tx.settled == nil
  end

  test "from_json/1 with an expanded (object) merchant" do
    json = %{
      "id" => "tx_1",
      "amount" => -100,
      "created" => "2020-01-01T00:00:00Z",
      "currency" => "GBP",
      "description" => "Coffee",
      "metadata" => %{},
      "notes" => "",
      "is_load" => false,
      "settled" => "2020-01-02T00:00:00Z",
      "merchant" => %{"id" => "merch_1", "name" => "Cafe", "group_id" => "g1"}
    }

    tx = Transaction.from_json(json)

    assert tx.merchant_id == "merch_1"
    assert tx.merchant.name == "Cafe"
    assert tx.settled == ~U[2020-01-02 00:00:00Z]
  end

  test "from_json/1 with a nil merchant" do
    json = %{
      "id" => "tx_1",
      "amount" => -100,
      "created" => "2020-01-01T00:00:00Z",
      "currency" => "GBP",
      "description" => "Coffee",
      "metadata" => %{},
      "notes" => "",
      "is_load" => false,
      "settled" => "",
      "merchant" => nil
    }

    tx = Transaction.from_json(json)
    assert tx.merchant_id == nil
    assert tx.merchant == nil
  end

  test "from_json/1 parses decline_reason" do
    base = %{
      "id" => "tx_1",
      "amount" => -100,
      "created" => "2020-01-01T00:00:00Z",
      "currency" => "GBP",
      "description" => "Coffee",
      "metadata" => %{},
      "notes" => "",
      "is_load" => false,
      "settled" => ""
    }

    assert Transaction.from_json(Map.put(base, "decline_reason", "INSUFFICIENT_FUNDS")).decline_reason ==
             :insufficient_funds

    assert Transaction.from_json(Map.put(base, "decline_reason", "CARD_BLOCKED")).decline_reason ==
             :card_blocked

    assert Transaction.from_json(base).decline_reason == nil
  end

  test "cursor_value/1 formats the created timestamp as RFC3339" do
    tx = %Transaction{created: ~U[2020-01-02 03:04:05Z]}
    assert Transaction.cursor_value(tx) == "2020-01-02T03:04:05Z"
  end

  test "cursor_value/1 returns nil when created is nil" do
    assert Transaction.cursor_value(%Transaction{created: nil}) == nil
  end
end
