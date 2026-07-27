defmodule Monzo.WebhooksTest do
  use ExUnit.Case, async: true

  alias Monzo.Test.MockAdapter
  alias Monzo.Webhook

  defp client(agent) do
    Monzo.Client.new(
      base_url: "https://api.monzo.com",
      adapter: MockAdapter.adapter(agent),
      access_token: "t"
    )
  end

  test "register/3 registers a webhook" do
    {:ok, agent} =
      MockAdapter.start_link([
        MockAdapter.json_response(%{
          "webhook" => %{
            "id" => "webhook_1",
            "account_id" => "acc_1",
            "url" => "https://x.com/hook"
          }
        })
      ])

    assert {:ok, webhook} = Monzo.Webhooks.register(client(agent), "acc_1", "https://x.com/hook")
    assert webhook.id == "webhook_1"
  end

  test "list/2 lists webhooks for an account" do
    {:ok, agent} =
      MockAdapter.start_link([
        MockAdapter.json_response(%{
          "webhooks" => [
            %{"id" => "webhook_1", "account_id" => "acc_1", "url" => "https://x.com/hook"}
          ]
        })
      ])

    assert {:ok, [webhook]} = Monzo.Webhooks.list(client(agent), "acc_1")
    assert webhook.id == "webhook_1"

    [req] = MockAdapter.requests(agent)
    assert req.url == "https://api.monzo.com/webhooks?account_id=acc_1"
  end

  test "delete/2 deletes a webhook by id" do
    {:ok, agent} = MockAdapter.start_link([MockAdapter.empty_response()])
    assert :ok = Monzo.Webhooks.delete(client(agent), "webhook_1")

    [req] = MockAdapter.requests(agent)
    assert req.url == "https://api.monzo.com/webhooks/webhook_1"
    assert req.method == :delete
  end

  @raw_transaction_created ~s({
    "type": "transaction.created",
    "data": {
      "id": "tx_1",
      "account_id": "acc_1",
      "amount": -350,
      "created": "2015-09-04T14:28:40Z",
      "currency": "GBP",
      "description": "Ozone Coffee Roasters",
      "category": "eating_out",
      "is_load": false,
      "settled": "2015-09-05T14:28:40Z",
      "merchant": {"id": "merch_1", "name": "Ozone"}
    }
  })

  test "parse_event/1 parses a valid transaction.created payload" do
    assert {:ok, %Webhook.Event{type: "transaction.created", data: data}} =
             Monzo.Webhooks.parse_event(@raw_transaction_created)

    assert data.id == "tx_1"
    assert data.account_id == "acc_1"
  end

  test "parse_event/1 returns an error for invalid JSON" do
    assert {:error, %Monzo.Error.WebhookVerificationError{}} =
             Monzo.Webhooks.parse_event("not json")
  end

  test "parse_event/1 returns an error for a payload missing type/data" do
    assert {:error, %Monzo.Error.WebhookVerificationError{}} =
             Monzo.Webhooks.parse_event(~s({"foo":"bar"}))
  end

  test "assert_expected_account/2 passes when the account_id is allow-listed" do
    {:ok, event} = Monzo.Webhooks.parse_event(@raw_transaction_created)
    assert :ok = Monzo.Webhooks.assert_expected_account(event, ["acc_1", "acc_2"])
  end

  test "assert_expected_account/2 fails when the account_id is not expected" do
    {:ok, event} = Monzo.Webhooks.parse_event(@raw_transaction_created)

    assert {:error, %Monzo.Error.WebhookVerificationError{}} =
             Monzo.Webhooks.assert_expected_account(event, ["acc_other"])
  end
end
