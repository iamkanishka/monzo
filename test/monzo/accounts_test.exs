defmodule Monzo.AccountsTest do
  use ExUnit.Case, async: true

  alias Monzo.Test.MockAdapter

  defp client(agent, opts \\ []) do
    Monzo.Client.new(
      Keyword.merge(
        [
          base_url: "https://api.monzo.com",
          adapter: MockAdapter.adapter(agent),
          access_token: "t"
        ],
        opts
      )
    )
  end

  test "list/2 returns accounts" do
    {:ok, agent} =
      MockAdapter.start_link([
        MockAdapter.json_response(%{
          "accounts" => [
            %{"id" => "acc_1", "description" => "Main", "created" => "2020-01-01T00:00:00Z"}
          ]
        })
      ])

    assert {:ok, [account]} = Monzo.Accounts.list(client(agent))
    assert account.id == "acc_1"
    assert account.created == ~U[2020-01-01 00:00:00Z]
  end

  test "list/2 filters by account_type" do
    {:ok, agent} = MockAdapter.start_link([MockAdapter.json_response(%{"accounts" => []})])
    Monzo.Accounts.list(client(agent), %{type: :uk_retail_joint})

    [req] = MockAdapter.requests(agent)
    assert req.url == "https://api.monzo.com/accounts?account_type=uk_retail_joint"
  end
end
