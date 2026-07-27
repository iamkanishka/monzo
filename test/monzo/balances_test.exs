defmodule Monzo.BalancesTest do
  use ExUnit.Case, async: true

  alias Monzo.Test.MockAdapter

  defp client(agent) do
    Monzo.Client.new(
      base_url: "https://api.monzo.com",
      adapter: MockAdapter.adapter(agent),
      access_token: "t"
    )
  end

  test "read/2 returns the balance for an account" do
    {:ok, agent} =
      MockAdapter.start_link([
        MockAdapter.json_response(%{
          "balance" => 5000,
          "total_balance" => 5000,
          "currency" => "GBP",
          "spend_today" => 0
        })
      ])

    assert {:ok, balance} = Monzo.Balances.read(client(agent), "acc_1")
    assert balance.balance == 5000
    [req] = MockAdapter.requests(agent)
    assert req.url == "https://api.monzo.com/balance?account_id=acc_1"
  end

  test "read/2 rejects an empty account id" do
    {:ok, agent} = MockAdapter.start_link([])

    assert {:error, %Monzo.Error.ValidationError{field: :account_id}} =
             Monzo.Balances.read(client(agent), "")

    assert MockAdapter.call_count(agent) == 0
  end
end
