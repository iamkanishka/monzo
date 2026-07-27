defmodule Monzo.Auth do
  @moduledoc """
  The OAuth2 authentication flow: building the authorization URL,
  exchanging a code, refreshing tokens, logging out, and token introspection.

  Most applications don't call `exchange_code/2` or `refresh_token/2`
  directly - `Monzo.Client` and its `Monzo.TokenStore` handle the token
  lifecycle automatically. This module is here for the initial
  authorization-code exchange (which necessarily happens before you have a
  client with tokens) and for advanced manual control.
  """

  alias Monzo.Auth.{Token, WhoAmI}
  alias Monzo.Client
  alias Monzo.Error.ValidationError
  alias Monzo.HTTP

  @authorize_base_url "https://auth.monzo.com/"

  @type authorization_url_params :: %{
          required(:client_id) => String.t(),
          required(:redirect_uri) => String.t(),
          required(:state) => String.t()
        }

  @doc """
  Builds the URL to send a user's browser to in order to begin the OAuth2
  authorization-code flow.

  Always generate and persist a random `:state` value (see
  `Monzo.Security.generate_state/1`) and verify it on callback with
  `Monzo.Security.constant_time_equal?/2`.
  """
  @spec build_authorization_url(authorization_url_params()) ::
          {:ok, String.t()} | {:error, ValidationError.t()}
  def build_authorization_url(params) do
    with :ok <- require_present(params, :client_id),
         :ok <- require_present(params, :redirect_uri),
         :ok <- require_present(params, :state) do
      query =
        URI.encode_query(%{
          "client_id" => params.client_id,
          "redirect_uri" => params.redirect_uri,
          "response_type" => "code",
          "state" => params.state
        })

      {:ok, @authorize_base_url <> "?" <> query}
    end
  end

  @doc "Same as `build_authorization_url/1` but raises on invalid input."
  @spec build_authorization_url!(authorization_url_params()) :: String.t()
  def build_authorization_url!(params) do
    case build_authorization_url(params) do
      {:ok, url} -> url
      {:error, error} -> raise error
    end
  end

  @type exchange_code_params :: %{
          required(:client_id) => String.t(),
          required(:client_secret) => String.t(),
          required(:redirect_uri) => String.t(),
          required(:code) => String.t()
        }

  @doc """
  Exchanges a temporary authorization code (from the OAuth callback) for an
  access token. `client` need not have any tokens configured yet.
  """
  @spec exchange_code(Client.t(), exchange_code_params()) ::
          {:ok, Token.t()} | {:error, Exception.t()}
  def exchange_code(%Client{} = client, params) do
    request =
      HTTP.request(client,
        method: :post,
        path: "/oauth2/token",
        encoding: :form,
        form: %{
          "grant_type" => "authorization_code",
          "client_id" => params.client_id,
          "client_secret" => params.client_secret,
          "redirect_uri" => params.redirect_uri,
          "code" => params.code
        },
        idempotent: false
      )

    with {:ok, json} <- request, do: {:ok, Token.from_json(json)}
  end

  @type refresh_token_params :: %{
          required(:client_id) => String.t(),
          required(:client_secret) => String.t(),
          required(:refresh_token) => String.t()
        }

  @doc """
  Exchanges a refresh token for a new access token. This is a one-time-use
  operation on the refresh token - Monzo issues a new one alongside the
  new access token.
  """
  @spec refresh_token(Client.t(), refresh_token_params()) ::
          {:ok, Token.t()} | {:error, Exception.t()}
  def refresh_token(%Client{} = client, params) do
    request =
      HTTP.request(client,
        method: :post,
        path: "/oauth2/token",
        encoding: :form,
        form: %{
          "grant_type" => "refresh_token",
          "client_id" => params.client_id,
          "client_secret" => params.client_secret,
          "refresh_token" => params.refresh_token
        },
        idempotent: false
      )

    with {:ok, json} <- request, do: {:ok, Token.from_json(json)}
  end

  @doc "Immediately invalidates the client's current access token server-side."
  @spec logout(Client.t()) :: :ok | {:error, Exception.t()}
  def logout(%Client{} = client) do
    case HTTP.request(client, method: :post, path: "/oauth2/logout", idempotent: false) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc "Returns metadata about the client's currently configured access token."
  @spec who_am_i(Client.t()) :: {:ok, WhoAmI.t()} | {:error, Exception.t()}
  def who_am_i(%Client{} = client) do
    with {:ok, json} <- HTTP.request(client, method: :get, path: "/ping/whoami") do
      {:ok, WhoAmI.from_json(json)}
    end
  end

  defp require_present(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> :ok
      _ -> {:error, %ValidationError{field: key, message: "must not be empty"}}
    end
  end
end
