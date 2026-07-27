defmodule Monzo.TokenStoreTest do
  use ExUnit.Case, async: true

  alias Monzo.Test.MockAdapter
  alias Monzo.TokenStore

  defp start_store(agent, opts \\ []) do
    default_opts = [
      access_token: "initial",
      adapter: MockAdapter.adapter(agent),
      base_url: "https://api.monzo.com"
    ]

    {:ok, pid} = TokenStore.start_link(Keyword.merge(default_opts, opts))
    pid
  end

  test "access_token/1 returns the configured token" do
    {:ok, agent} = MockAdapter.start_link([])
    store = start_store(agent)
    assert TokenStore.access_token(store) == "initial"
  end

  test "set_tokens/3 updates the access token, keeping refresh_token if not provided" do
    {:ok, agent} = MockAdapter.start_link([])
    store = start_store(agent, refresh_token: "original-refresh")

    :ok = TokenStore.set_tokens(store, "updated")
    assert TokenStore.access_token(store) == "updated"
  end

  test "refresh/1 returns an error when no refresh credentials are configured" do
    {:ok, agent} = MockAdapter.start_link([])
    store = start_store(agent)

    assert {:error, :no_refresh_credentials} = TokenStore.refresh(store)
  end

  test "refresh/1 calls the API, updates state, and invokes the on_refresh callback" do
    {:ok, agent} =
      MockAdapter.start_link([
        MockAdapter.json_response(%{
          "access_token" => "new-token",
          "refresh_token" => "new-refresh",
          "client_id" => "cid",
          "user_id" => "uid",
          "expires_in" => 21_600,
          "token_type" => "Bearer"
        })
      ])

    test_pid = self()

    store =
      start_store(agent,
        refresh_token: "old-refresh",
        client_id: "cid",
        client_secret: "secret",
        on_refresh: fn access, refresh -> send(test_pid, {:refreshed, access, refresh}) end
      )

    assert {:ok, "new-token"} = TokenStore.refresh(store)
    assert TokenStore.access_token(store) == "new-token"
    assert_received {:refreshed, "new-token", "new-refresh"}
  end

  test "refresh/1 surfaces API errors without crashing the store" do
    {:ok, agent} = MockAdapter.start_link([MockAdapter.json_response(500, %{})])
    store = start_store(agent, refresh_token: "rt", client_id: "cid", client_secret: "secret")

    assert {:error, %Monzo.Error.APIError{status: 500}} = TokenStore.refresh(store)
    assert Process.alive?(store)
  end

  test "start_supervised/1 starts a child under the DynamicSupervisor" do
    {:ok, agent} = MockAdapter.start_link([])

    assert {:ok, pid} =
             TokenStore.start_supervised(
               access_token: "t",
               adapter: MockAdapter.adapter(agent),
               base_url: "https://api.monzo.com"
             )

    assert Process.alive?(pid)
    assert TokenStore.access_token(pid) == "t"
  end
end
