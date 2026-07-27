defmodule Monzo.AuthTest do
  use ExUnit.Case, async: true

  alias Monzo.Test.MockAdapter

  defp client(agent) do
    Monzo.Client.new(base_url: "https://api.monzo.com", adapter: MockAdapter.adapter(agent))
  end

  test "build_authorization_url/1 builds a well-formed URL" do
    assert {:ok, url} =
             Monzo.Auth.build_authorization_url(%{
               client_id: "client_abc",
               redirect_uri: "https://app.example.com/callback",
               state: "xyz123"
             })

    uri = URI.parse(url)
    assert uri.host == "auth.monzo.com"
    query = URI.decode_query(uri.query)
    assert query["client_id"] == "client_abc"
    assert query["redirect_uri"] == "https://app.example.com/callback"
    assert query["response_type"] == "code"
    assert query["state"] == "xyz123"
  end

  test "build_authorization_url/1 rejects a missing state" do
    assert {:error, %Monzo.Error.ValidationError{field: :state}} =
             Monzo.Auth.build_authorization_url(%{
               client_id: "c",
               redirect_uri: "https://x.com",
               state: ""
             })
  end

  test "build_authorization_url!/1 raises on invalid input" do
    assert_raise Monzo.Error.ValidationError, fn ->
      Monzo.Auth.build_authorization_url!(%{
        client_id: "",
        redirect_uri: "https://x.com",
        state: "s"
      })
    end
  end

  test "exchange_code/2 exchanges a code via form-encoded POST" do
    {:ok, agent} =
      MockAdapter.start_link([
        MockAdapter.json_response(%{
          "access_token" => "at",
          "refresh_token" => "rt",
          "client_id" => "cid",
          "user_id" => "uid",
          "expires_in" => 21_600,
          "token_type" => "Bearer"
        })
      ])

    assert {:ok, token} =
             Monzo.Auth.exchange_code(client(agent), %{
               client_id: "cid",
               client_secret: "secret",
               redirect_uri: "https://app.example.com/cb",
               code: "authcode"
             })

    assert token.access_token == "at"

    [req] = MockAdapter.requests(agent)
    assert req.url == "https://api.monzo.com/oauth2/token"
    decoded = URI.decode_query(req.body)
    assert decoded["grant_type"] == "authorization_code"
  end

  test "refresh_token/2 refreshes an access token" do
    {:ok, agent} =
      MockAdapter.start_link([
        MockAdapter.json_response(%{
          "access_token" => "at2",
          "refresh_token" => "rt2",
          "client_id" => "cid",
          "user_id" => "uid",
          "expires_in" => 21_600,
          "token_type" => "Bearer"
        })
      ])

    assert {:ok, token} =
             Monzo.Auth.refresh_token(client(agent), %{
               client_id: "cid",
               client_secret: "secret",
               refresh_token: "rt"
             })

    assert token.access_token == "at2"

    [req] = MockAdapter.requests(agent)
    decoded = URI.decode_query(req.body)
    assert decoded["grant_type"] == "refresh_token"
  end

  test "who_am_i/1 returns token metadata" do
    {:ok, agent} =
      MockAdapter.start_link([
        MockAdapter.json_response(%{
          "authenticated" => true,
          "client_id" => "cid",
          "user_id" => "uid"
        })
      ])

    assert {:ok, who} = Monzo.Auth.who_am_i(client(agent))
    assert who.authenticated
  end

  test "logout/1 invalidates the token" do
    {:ok, agent} = MockAdapter.start_link([MockAdapter.empty_response()])
    assert :ok = Monzo.Auth.logout(client(agent))
  end
end
