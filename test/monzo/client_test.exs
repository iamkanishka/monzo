defmodule Monzo.ClientTest do
  use ExUnit.Case, async: true

  alias Monzo.Client
  alias Monzo.Test.MockAdapter

  test "new/1 builds a client with default configuration" do
    {:ok, agent} = MockAdapter.start_link([])
    client = Client.new(adapter: MockAdapter.adapter(agent))

    assert client.base_url == "https://api.monzo.com"
    assert client.user_agent =~ "monzo-elixir/"
    assert client.retry.max_retries == 2
    assert is_pid(client.token_store)
  end

  test "new/1 respects overrides" do
    {:ok, agent} = MockAdapter.start_link([])

    client =
      Client.new(
        adapter: MockAdapter.adapter(agent),
        base_url: "https://sandbox.example.com",
        timeout_ms: 5_000,
        user_agent: "my-app/1.0",
        retry: %{max_retries: 5}
      )

    assert client.base_url == "https://sandbox.example.com"
    assert client.timeout_ms == 5_000
    assert client.user_agent == "my-app/1.0"
    assert client.retry.max_retries == 5
    # unspecified retry fields keep their defaults
    assert client.retry.base_delay_ms == 250
  end

  test "access_token/1 and set_tokens/3 round-trip through the token store" do
    {:ok, agent} = MockAdapter.start_link([])
    client = Client.new(adapter: MockAdapter.adapter(agent), access_token: "initial")

    assert Client.access_token(client) == "initial"
    Client.set_tokens(client, "updated", "refresh")
    assert Client.access_token(client) == "updated"
  end

  test "refresh/1 returns an error when the token store has no refresh credentials" do
    {:ok, agent} = MockAdapter.start_link([])
    client = Client.new(adapter: MockAdapter.adapter(agent), access_token: "t")

    assert {:error, :no_refresh_credentials} = Client.refresh(client)
  end

  test "accepts an already-running token store via :token_store" do
    {:ok, agent} = MockAdapter.start_link([])

    {:ok, store} =
      Monzo.TokenStore.start_link(
        access_token: "shared",
        adapter: MockAdapter.adapter(agent),
        base_url: "https://api.monzo.com"
      )

    client_a = Client.new(adapter: MockAdapter.adapter(agent), token_store: store)
    client_b = Client.new(adapter: MockAdapter.adapter(agent), token_store: store)

    Client.set_tokens(client_a, "shared-updated")
    assert Client.access_token(client_b) == "shared-updated"
  end
end
