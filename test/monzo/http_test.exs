defmodule Monzo.HTTPTest do
  use ExUnit.Case, async: true

  alias Monzo.Client
  alias Monzo.Error.{APIError, NetworkError, TimeoutError}
  alias Monzo.Test.MockAdapter

  defp start_mock(responders) do
    {:ok, agent} = MockAdapter.start_link(responders)
    agent
  end

  defp client(agent, opts) do
    Client.new(
      Keyword.merge(
        [base_url: "https://api.monzo.com", adapter: MockAdapter.adapter(agent)],
        opts
      )
    )
  end

  test "attaches the bearer token and builds the query string" do
    agent = start_mock([MockAdapter.json_response(%{"ok" => true})])
    client = client(agent, access_token: "token123")

    assert {:ok, %{"ok" => true}} =
             Monzo.HTTP.request(client,
               method: :get,
               path: "/accounts",
               query: %{"account_type" => "uk_retail"}
             )

    [req] = MockAdapter.requests(agent)
    assert req.url == "https://api.monzo.com/accounts?account_type=uk_retail"
    assert {"authorization", "Bearer token123"} in req.headers
  end

  test "form-encodes the body for :form requests" do
    agent = start_mock([MockAdapter.json_response(%{"ok" => true})])
    client = client(agent, access_token: "t")

    Monzo.HTTP.request(client,
      method: :post,
      path: "/pots/x/deposit",
      encoding: :form,
      form: %{"amount" => 100, "dedupe_id" => "abc"}
    )

    [req] = MockAdapter.requests(agent)
    assert req.body == "amount=100&dedupe_id=abc"
    assert {"content-type", "application/x-www-form-urlencoded"} in req.headers
  end

  test "JSON-encodes the body for :json requests" do
    agent = start_mock([MockAdapter.json_response(%{"receipt_id" => "r1"})])
    client = client(agent, access_token: "t")

    {:ok, %{"receipt_id" => "r1"}} =
      Monzo.HTTP.request(client,
        method: :put,
        path: "/transaction-receipts",
        encoding: :json,
        json: %{"total" => 100}
      )

    [req] = MockAdapter.requests(agent)
    assert req.body == "{\"total\":100}"
    assert {"content-type", "application/json"} in req.headers
  end

  test "returns an APIError with parsed body on non-2xx responses" do
    agent =
      start_mock([
        MockAdapter.json_response(401, %{
          "error" => "invalid_token",
          "error_description" => "expired"
        })
      ])

    client = client(agent, access_token: "t")

    assert {:error, %APIError{status: 401, code: "invalid_token", message: "expired"}} =
             Monzo.HTTP.request(client, method: :get, path: "/accounts")
  end

  test "APIError.invalid_token?/1 is true for 401s" do
    agent = start_mock([MockAdapter.json_response(401, %{"error" => "invalid_token"})])
    client = client(agent, access_token: "t")

    {:error, error} = Monzo.HTTP.request(client, method: :get, path: "/accounts")
    assert APIError.invalid_token?(error)
  end

  test "retries transient 500 errors up to max_retries with backoff" do
    agent =
      start_mock([
        MockAdapter.json_response(500, %{}),
        MockAdapter.json_response(500, %{}),
        MockAdapter.json_response(%{"ok" => true})
      ])

    client =
      client(agent,
        access_token: "t",
        retry: %{max_retries: 2, base_delay_ms: 1, max_delay_ms: 2}
      )

    assert {:ok, %{"ok" => true}} = Monzo.HTTP.request(client, method: :get, path: "/accounts")
    assert MockAdapter.call_count(agent) == 3
  end

  test "does not retry non-idempotent requests on 500" do
    agent = start_mock([MockAdapter.json_response(500, %{})])

    client =
      client(agent,
        access_token: "t",
        retry: %{max_retries: 2, base_delay_ms: 1, max_delay_ms: 2}
      )

    assert {:error, %APIError{}} =
             Monzo.HTTP.request(client,
               method: :post,
               path: "/feed",
               encoding: :form,
               form: %{},
               idempotent: false
             )

    assert MockAdapter.call_count(agent) == 1
  end

  test "gives up after max_retries and returns the last error" do
    agent =
      start_mock([
        MockAdapter.json_response(500, %{}),
        MockAdapter.json_response(500, %{}),
        MockAdapter.json_response(500, %{})
      ])

    client =
      client(agent,
        access_token: "t",
        retry: %{max_retries: 2, base_delay_ms: 1, max_delay_ms: 2}
      )

    assert {:error, %APIError{status: 500}} =
             Monzo.HTTP.request(client, method: :get, path: "/accounts")

    assert MockAdapter.call_count(agent) == 3
  end

  test "refreshes the token once on 401 and retries with the new token" do
    agent =
      start_mock([
        MockAdapter.json_response(401, %{"error" => "invalid_token"}),
        MockAdapter.json_response(%{
          "access_token" => "fresh-token",
          "refresh_token" => "fresh-refresh",
          "client_id" => "cid",
          "user_id" => "uid",
          "expires_in" => 21_600,
          "token_type" => "Bearer"
        }),
        MockAdapter.json_response(%{"accounts" => []})
      ])

    client =
      client(agent,
        access_token: "stale-token",
        refresh_token: "refresh-token",
        client_id: "cid",
        client_secret: "secret"
      )

    assert {:ok, %{"accounts" => []}} =
             Monzo.HTTP.request(client, method: :get, path: "/accounts")

    requests = MockAdapter.requests(agent)
    assert length(requests) == 3
    last_request = List.last(requests)
    assert {"authorization", "Bearer fresh-token"} in last_request.headers
    assert Client.access_token(client) == "fresh-token"
  end

  test "does not loop forever if refresh also yields a 401" do
    agent =
      start_mock([
        MockAdapter.json_response(401, %{"error" => "invalid_token"}),
        MockAdapter.json_response(401, %{"error" => "invalid_token"})
      ])

    client =
      client(agent,
        access_token: "stale",
        refresh_token: "still-bad",
        client_id: "cid",
        client_secret: "secret"
      )

    assert {:error, %APIError{status: 401}} =
             Monzo.HTTP.request(client, method: :get, path: "/accounts")

    assert MockAdapter.call_count(agent) == 2
  end

  test "surfaces the original 401 when no refresh credentials are configured" do
    agent = start_mock([MockAdapter.json_response(401, %{"error" => "invalid_token"})])
    client = client(agent, access_token: "stale")

    assert {:error, %APIError{status: 401}} =
             Monzo.HTTP.request(client, method: :get, path: "/accounts")

    assert MockAdapter.call_count(agent) == 1
  end

  test "wraps network errors and retries idempotent requests" do
    agent =
      start_mock([
        MockAdapter.error_response(:econnrefused),
        MockAdapter.json_response(%{"ok" => true})
      ])

    client =
      client(agent,
        access_token: "t",
        retry: %{max_retries: 2, base_delay_ms: 1, max_delay_ms: 2}
      )

    assert {:ok, %{"ok" => true}} = Monzo.HTTP.request(client, method: :get, path: "/accounts")
    assert MockAdapter.call_count(agent) == 2
  end

  test "does not retry non-idempotent requests on network error" do
    agent = start_mock([MockAdapter.error_response(:econnrefused)])
    client = client(agent, access_token: "t")

    assert {:error, %NetworkError{}} =
             Monzo.HTTP.request(client,
               method: :post,
               path: "/feed",
               encoding: :form,
               form: %{},
               idempotent: false
             )

    assert MockAdapter.call_count(agent) == 1
  end

  test "raises TimeoutError for timeout responses" do
    agent = start_mock([MockAdapter.timeout_response()])
    client = client(agent, access_token: "t")

    assert {:error, %TimeoutError{path: "/accounts"}} =
             Monzo.HTTP.request(client, method: :get, path: "/accounts")
  end

  test "returns an empty map for empty response bodies" do
    agent = start_mock([MockAdapter.empty_response(204)])
    client = client(agent, access_token: "t")

    assert {:ok, %{}} = Monzo.HTTP.request(client, method: :delete, path: "/webhooks/x")
  end

  test "repeats expand[] style array query params" do
    agent = start_mock([MockAdapter.json_response(%{"transaction" => %{}})])
    client = client(agent, access_token: "t")

    Monzo.HTTP.request(client,
      method: :get,
      path: "/transactions/tx_1",
      query: %{"expand[]" => ["merchant"]}
    )

    [req] = MockAdapter.requests(agent)
    assert req.url == "https://api.monzo.com/transactions/tx_1?expand%5B%5D=merchant"
  end

  test "GET is idempotent by default; POST is not" do
    agent = start_mock([MockAdapter.json_response(500, %{}), MockAdapter.json_response(500, %{})])

    client =
      client(agent,
        access_token: "t",
        retry: %{max_retries: 1, base_delay_ms: 1, max_delay_ms: 2}
      )

    Monzo.HTTP.request(client, method: :get, path: "/accounts")
    assert MockAdapter.call_count(agent) == 2
  end
end
