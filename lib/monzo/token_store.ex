defmodule Monzo.TokenStore do
  @moduledoc """
  A supervised `GenServer` holding the current access/refresh token pair
  for one Monzo user, and performing the actual refresh call.

  You normally don't interact with this module directly - `Monzo.Client`
  starts and owns one automatically. It's exposed publicly for advanced
  use cases: sharing a single token store across multiple clients, or
  wiring it into your own supervision tree with a registered `:name`.
  """

  use GenServer

  alias Monzo.Auth

  defstruct [
    :access_token,
    :refresh_token,
    :client_id,
    :client_secret,
    :on_refresh,
    :adapter,
    :base_url
  ]

  @type t :: %__MODULE__{
          access_token: String.t() | nil,
          refresh_token: String.t() | nil,
          client_id: String.t() | nil,
          client_secret: String.t() | nil,
          on_refresh: (String.t(), String.t() | nil -> any()) | nil,
          adapter: module(),
          base_url: String.t()
        }

  @doc "Starts a token store under `Monzo.TokenStore.Supervisor`, unlinked from the caller."
  @spec start_supervised(keyword()) :: DynamicSupervisor.on_start_child()
  def start_supervised(opts) do
    DynamicSupervisor.start_child(Monzo.TokenStore.Supervisor, {__MODULE__, opts})
  end

  @doc "Starts a token store process directly (e.g. under your own supervision tree)."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Returns the current access token, or nil."
  @spec access_token(GenServer.server()) :: String.t() | nil
  def access_token(server), do: GenServer.call(server, :access_token)

  @doc "Manually sets new tokens (e.g. after completing the OAuth flow)."
  @spec set_tokens(GenServer.server(), String.t(), String.t() | nil) :: :ok
  def set_tokens(server, access_token, refresh_token \\ nil) do
    GenServer.call(server, {:set_tokens, access_token, refresh_token})
  end

  @doc """
  Refreshes the access token using the stored refresh token and client
  credentials. Returns `{:error, :no_refresh_credentials}` without making
  any request if they aren't configured.
  """
  @spec refresh(GenServer.server()) :: {:ok, String.t()} | {:error, term()}
  def refresh(server), do: GenServer.call(server, :refresh)

  ## GenServer callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      access_token: Keyword.get(opts, :access_token),
      refresh_token: Keyword.get(opts, :refresh_token),
      client_id: Keyword.get(opts, :client_id),
      client_secret: Keyword.get(opts, :client_secret),
      on_refresh: Keyword.get(opts, :on_refresh),
      adapter: Keyword.get(opts, :adapter, Monzo.HTTP.HttpcAdapter),
      base_url: Keyword.get(opts, :base_url, "https://api.monzo.com")
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:access_token, _from, state) do
    {:reply, state.access_token, state}
  end

  @impl true
  def handle_call({:set_tokens, access_token, refresh_token}, _from, state) do
    state =
      %{state | access_token: access_token}
      |> maybe_put_refresh_token(refresh_token)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:refresh, _from, state) do
    if state.refresh_token && state.client_id && state.client_secret do
      # A bare, unauthenticated client (no token store dependency) is used
      # for the refresh call itself so it doesn't recursively depend on
      # this same token store for its own auth header.
      bare_client = %Monzo.Client{
        base_url: state.base_url,
        adapter: state.adapter,
        retry: Monzo.HTTP.default_retry_policy(),
        logger: fn _level, _message -> :ok end,
        user_agent: "monzo-elixir",
        token_store: nil
      }

      case Auth.refresh_token(bare_client, %{
             client_id: state.client_id,
             client_secret: state.client_secret,
             refresh_token: state.refresh_token
           }) do
        {:ok, token} ->
          new_state =
            %{state | access_token: token.access_token}
            |> maybe_put_refresh_token(token.refresh_token)

          if state.on_refresh, do: state.on_refresh.(token.access_token, new_state.refresh_token)

          {:reply, {:ok, token.access_token}, new_state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, :no_refresh_credentials}, state}
    end
  end

  defp maybe_put_refresh_token(state, nil), do: state
  defp maybe_put_refresh_token(state, refresh_token), do: %{state | refresh_token: refresh_token}

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end
end
