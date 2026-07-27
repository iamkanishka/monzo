defmodule Monzo.Client do
  @moduledoc """
  Immutable client configuration passed to every `Monzo` resource function.

  Construct one with `new/1`. Mutable state (the current access/refresh
  token pair) lives in a supervised `Monzo.TokenStore` process referenced
  by `token_store`, not in this struct - so a `%Monzo.Client{}` is safe to
  share across processes and store in application config.

  ## Options

    * `:access_token` - the user's current access token.
    * `:refresh_token` - enables automatic refresh-on-401, together with
      `:client_id` and `:client_secret`.
    * `:client_id` / `:client_secret` - required for token exchange, manual
      refresh, and automatic 401 recovery.
    * `:on_refresh` - a `(access_token, refresh_token -> any)` callback
      invoked whenever the token store successfully refreshes, so you can
      persist the rotated tokens (Monzo refresh tokens are single-use).
    * `:base_url` - defaults to `"https://api.monzo.com"`. Override for
      testing against a mock server.
    * `:adapter` - a module implementing `Monzo.HTTP.Adapter`. Defaults to
      `Monzo.HTTP.HttpcAdapter`.
    * `:timeout_ms` - per-request timeout, defaults to 15000.
    * `:retry` - a map with `:max_retries`, `:base_delay_ms`, `:max_delay_ms`
      overriding the default retry policy.
    * `:logger` - a `(level, message -> any)` function for debug/warn
      events. Defaults to a no-op.
    * `:user_agent` - defaults to `"monzo-elixir/<version>"`.
    * `:token_store` - an already-running `Monzo.TokenStore` pid or
      registered name to reuse, instead of starting a new one. Useful when
      multiple `%Monzo.Client{}` structs should share one token store.

  ## Example

      client = Monzo.Client.new(
        access_token: System.fetch_env!("MONZO_ACCESS_TOKEN"),
        refresh_token: System.fetch_env!("MONZO_REFRESH_TOKEN"),
        client_id: System.fetch_env!("MONZO_CLIENT_ID"),
        client_secret: System.fetch_env!("MONZO_CLIENT_SECRET"),
        on_refresh: fn access, refresh -> MyApp.Tokens.persist(access, refresh) end
      )

      {:ok, accounts} = Monzo.Accounts.list(client)
  """

  @default_base_url "https://api.monzo.com"
  @version Mix.Project.config()[:version] || "1.0.0"

  alias Monzo.TokenStore

  @enforce_keys [:base_url, :adapter, :user_agent, :retry, :logger]
  defstruct [
    :base_url,
    :adapter,
    :timeout_ms,
    :retry,
    :logger,
    :user_agent,
    :token_store
  ]

  @type retry_policy :: %{
          max_retries: non_neg_integer(),
          base_delay_ms: pos_integer(),
          max_delay_ms: pos_integer()
        }

  @type t :: %__MODULE__{
          base_url: String.t(),
          adapter: module(),
          timeout_ms: pos_integer() | nil,
          retry: retry_policy(),
          logger: (atom(), String.t() -> any()),
          user_agent: String.t(),
          token_store: GenServer.server() | nil
        }

  @doc "Builds a new client, starting a supervised token store."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    token_store =
      Keyword.get_lazy(opts, :token_store, fn ->
        {:ok, pid} =
          TokenStore.start_supervised(
            access_token: Keyword.get(opts, :access_token),
            refresh_token: Keyword.get(opts, :refresh_token),
            client_id: Keyword.get(opts, :client_id),
            client_secret: Keyword.get(opts, :client_secret),
            on_refresh: Keyword.get(opts, :on_refresh),
            adapter: Keyword.get(opts, :adapter, Monzo.HTTP.HttpcAdapter),
            base_url: Keyword.get(opts, :base_url, @default_base_url)
          )

        pid
      end)

    %__MODULE__{
      base_url: Keyword.get(opts, :base_url, @default_base_url),
      adapter: Keyword.get(opts, :adapter, Monzo.HTTP.HttpcAdapter),
      timeout_ms: Keyword.get(opts, :timeout_ms),
      retry: Map.merge(Monzo.HTTP.default_retry_policy(), Keyword.get(opts, :retry, %{})),
      logger: Keyword.get(opts, :logger, fn _level, _message -> :ok end),
      user_agent: Keyword.get(opts, :user_agent, "monzo-elixir/#{@version}"),
      token_store: token_store
    }
  end

  @doc "Returns the access token currently held by the client's token store, if any."
  @spec access_token(t()) :: String.t() | nil
  def access_token(%__MODULE__{token_store: nil}), do: nil
  def access_token(%__MODULE__{token_store: store}), do: TokenStore.access_token(store)

  @doc "Manually sets new tokens on the client's token store."
  @spec set_tokens(t(), String.t(), String.t() | nil) :: :ok
  def set_tokens(%__MODULE__{token_store: store}, access_token, refresh_token \\ nil) do
    TokenStore.set_tokens(store, access_token, refresh_token)
  end

  @doc """
  Forces a refresh of the access token using the configured refresh token
  and client credentials. Most callers don't need this - the client
  refreshes automatically on 401s.
  """
  @spec refresh(t()) :: {:ok, String.t()} | {:error, term()}
  def refresh(%__MODULE__{token_store: nil}), do: {:error, :no_token_store}
  def refresh(%__MODULE__{token_store: store}), do: TokenStore.refresh(store)
end
