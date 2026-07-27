defmodule Monzo.HTTP.Adapter do
  @moduledoc """
  Behaviour for the low-level HTTP transport used by `Monzo.HTTP`.

  The default implementation, `Monzo.HTTP.HttpcAdapter`, is built on
  Erlang's built-in `:httpc` (part of `:inets`), keeping `monzo` free of
  any required HTTP client dependency (Req, Finch, Tesla, HTTPoison, ...).

  Implement this behaviour to plug in your own HTTP client - useful for
  connection pooling in high-throughput applications, or for injecting a
  test double in your own test suite (see `Monzo.Test.MockAdapter` in this
  library's own tests for an example).
  """

  @type method :: :get | :post | :put | :patch | :delete
  @type headers :: [{String.t(), String.t()}]

  @type request :: %{
          method: method(),
          url: String.t(),
          headers: headers(),
          body: iodata() | nil,
          timeout_ms: pos_integer()
        }

  @type response :: %{
          status: pos_integer(),
          headers: headers(),
          body: binary()
        }

  @doc """
  Performs a single HTTP request and returns the raw response, or an
  error reason. Implementations should NOT retry - retry/backoff policy
  is handled by `Monzo.HTTP`.

  `opts` is whatever was configured as the adapter's options (see
  `Monzo.Client.new/1`'s `:adapter` option, which accepts either a bare
  module - in which case `opts` is `nil` - or a `{module, opts}` tuple).
  This lets test doubles carry explicit state (e.g. an Agent pid) instead
  of relying on process-dictionary globals, which would break across the
  process boundaries `Monzo.HTTP`'s retry loop and `Monzo.TokenStore`
  introduce.

  Return `{:error, {:timeout, reason}}` for timeouts specifically (so
  `Monzo.HTTP` can raise `Monzo.Error.TimeoutError` rather than a generic
  network error), and `{:error, reason}` for any other network failure.
  """
  @callback request(request(), opts :: term()) :: {:ok, response()} | {:error, term()}

  @doc false
  @spec dispatch(module() | {module(), term()}, request()) :: {:ok, response()} | {:error, term()}
  def dispatch({module, opts}, request), do: module.request(request, opts)
  def dispatch(module, request) when is_atom(module), do: module.request(request, nil)
end
