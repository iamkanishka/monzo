defmodule Monzo.PotsTest do
  use ExUnit.Case, async: true

  alias Monzo.Test.MockAdapter

  defp client(agent) do
    Monzo.Client.new(
      base_url: "https://api.monzo.com",
      adapter: MockAdapter.adapter(agent),
      access_token: "t"
    )
  end

  defp pot_json do
    %{
      "id" => "pot_1",
      "name" => "Savings",
      "style" => "beach_ball",
      "balance" => 133_700,
      "currency" => "GBP",
      "created" => "2017-11-09T12:30:53Z",
      "updated" => "2017-11-09T12:30:53Z",
      "deleted" => false
    }
  end

  test "list/2 returns pots for an account" do
    {:ok, agent} = MockAdapter.start_link([MockAdapter.json_response(%{"pots" => [pot_json()]})])
    assert {:ok, [pot]} = Monzo.Pots.list(client(agent), "acc_1")
    assert pot.id == "pot_1"
  end

  test "deposit/2 moves money into a pot" do
    {:ok, agent} = MockAdapter.start_link([MockAdapter.json_response(pot_json())])

    assert {:ok, pot} =
             Monzo.Pots.deposit(client(agent), %{
               pot_id: "pot_1",
               amount: 1000,
               dedupe_id: "d1",
               source_account_id: "acc_1"
             })

    assert pot.id == "pot_1"

    [req] = MockAdapter.requests(agent)
    assert req.url == "https://api.monzo.com/pots/pot_1/deposit"
    assert req.method == :put

    assert URI.decode_query(req.body) == %{
             "source_account_id" => "acc_1",
             "amount" => "1000",
             "dedupe_id" => "d1"
           }
  end

  test "withdraw/2 moves money out of a pot" do
    {:ok, agent} = MockAdapter.start_link([MockAdapter.json_response(pot_json())])

    assert {:ok, _pot} =
             Monzo.Pots.withdraw(client(agent), %{
               pot_id: "pot_1",
               amount: 500,
               dedupe_id: "d2",
               destination_account_id: "acc_1"
             })

    [req] = MockAdapter.requests(agent)
    assert req.url == "https://api.monzo.com/pots/pot_1/withdraw"
  end

  test "deposit/2 rejects non-positive amounts" do
    {:ok, agent} = MockAdapter.start_link([])

    assert {:error, %Monzo.Error.ValidationError{field: :amount}} =
             Monzo.Pots.deposit(client(agent), %{
               pot_id: "pot_1",
               amount: 0,
               dedupe_id: "d1",
               source_account_id: "acc_1"
             })

    assert MockAdapter.call_count(agent) == 0
  end

  test "deposit/2 rejects a missing dedupe_id" do
    {:ok, agent} = MockAdapter.start_link([])

    assert {:error, %Monzo.Error.ValidationError{field: :dedupe_id}} =
             Monzo.Pots.deposit(client(agent), %{
               pot_id: "pot_1",
               amount: 100,
               dedupe_id: "",
               source_account_id: "acc_1"
             })
  end

  test "pot id is URL-encoded" do
    {:ok, agent} = MockAdapter.start_link([MockAdapter.json_response(pot_json())])

    Monzo.Pots.deposit(client(agent), %{
      pot_id: "pot/weird id",
      amount: 100,
      dedupe_id: "d1",
      source_account_id: "acc_1"
    })

    [req] = MockAdapter.requests(agent)
    assert req.url == "https://api.monzo.com/pots/pot%2Fweird%20id/deposit"
  end
end
