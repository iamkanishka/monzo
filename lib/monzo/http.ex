defmodule Monzo.HTTP do
  @moduledoc """
  Core HTTP request engine shared by every resource module: URL/query/body
  encoding, bearer auth, jittered exponential-backoff retries on transient
  (429/5xx/network) failures, and a single automatic refresh-and-retry on
  401s when the client has a token store configured.

  This module is considered internal; resource modules like `Monzo.Accounts`
  are the intended public API.
  """

  alias Monzo.Client
  alias Monzo.Error.{APIError, NetworkError, TimeoutError}
  alias Monzo.HTTP.Adapter
  alias Monzo.JSON
  alias Monzo.TokenStore

  @type method :: :get | :post | :put | :patch | :delete
  @type body_encoding :: :none | :form | :json

  @type request_opts :: [
          method: method(),
          path: String.t(),
          query: %{optional(String.t()) => term()} | keyword(),
          encoding: body_encoding(),
          form: %{optional(String.t()) => term()},
          json: term(),
          access_token: String.t() | nil,
          idempotent: boolean() | nil
        ]

  @default_timeout_ms 15_000
  @default_max_retries 2
  @default_base_delay_ms 250
  @default_max_delay_ms 4_000

  @doc """
  Executes a request against the Monzo API described by `opts`, using the
  given `Monzo.Client` for configuration (base URL, adapter, token store,
  retry policy, etc), and returns the JSON-decoded response body.
  """
  @spec request(Client.t(), request_opts()) :: {:ok, term()} | {:error, Exception.t()}
  def request(%Client{} = client, opts) do
    do_request(client, normalize_opts(opts), 0, false)
  end

  defp normalize_opts(opts) do
    %{
      method: Keyword.fetch!(opts, :method),
      path: Keyword.fetch!(opts, :path),
      query: Keyword.get(opts, :query, %{}),
      encoding: Keyword.get(opts, :encoding, :none),
      form: Keyword.get(opts, :form, %{}),
      json: Keyword.get(opts, :json),
      access_token: Keyword.get(opts, :access_token),
      idempotent: Keyword.get(opts, :idempotent)
    }
  end

  defp do_request(client, opts, attempt, already_refreshed?) do
    case perform(client, opts) do
      {:ok, body} ->
        {:ok, body}

      {:error, %APIError{} = error} ->
        handle_api_error(client, opts, error, attempt, already_refreshed?)

      {:error, %NetworkError{}} = error ->
        handle_network_error(client, opts, error, attempt, already_refreshed?)

      other_error ->
        other_error
    end
  end

  defp handle_api_error(client, opts, error, attempt, already_refreshed?) do
    cond do
      should_refresh?(client, error, already_refreshed?) ->
        refresh_and_retry(client, opts, error, attempt)

      should_retry?(client, opts, error, attempt) ->
        retry_request(client, opts, attempt, already_refreshed?)

      true ->
        {:error, error}
    end
  end

  defp should_refresh?(client, error, already_refreshed?) do
    APIError.invalid_token?(error) and
      not already_refreshed? and
      client.token_store != nil
  end

  defp refresh_and_retry(client, opts, error, attempt) do
    case TokenStore.refresh(client.token_store) do
      {:ok, new_token} ->
        do_request(client, %{opts | access_token: new_token}, attempt, true)

      {:error, _reason} ->
        {:error, error}
    end
  end

  defp should_retry?(client, opts, error, attempt) do
    idempotent?(opts) and
      APIError.retryable?(error) and
      attempt < max_retries(client)
  end

  defp retry_request(client, opts, attempt, already_refreshed?) do
    Process.sleep(backoff_delay(client, attempt))
    do_request(client, opts, attempt + 1, already_refreshed?)
  end

  defp handle_network_error(client, opts, error, attempt, already_refreshed?) do
    if idempotent?(opts) and attempt < max_retries(client) do
      delay = backoff_delay(client, attempt)
      Process.sleep(delay)
      do_request(client, opts, attempt + 1, already_refreshed?)
    else
      error
    end
  end

  defp idempotent?(%{idempotent: nil, method: method}), do: method in [:get, :put, :delete]
  defp idempotent?(%{idempotent: idempotent?}), do: idempotent?

  defp max_retries(%Client{retry: retry}), do: retry.max_retries

  defp backoff_delay(%Client{retry: retry}, attempt) do
    exp = min(retry.base_delay_ms * Integer.pow(2, attempt), retry.max_delay_ms)
    :rand.uniform(exp + 1) - 1
  end

  defp perform(client, opts) do
    url = build_url(client, opts)
    {content_type, body} = encode_body(opts)

    token =
      opts.access_token ||
        (client.token_store && TokenStore.access_token(client.token_store))

    headers =
      [{"accept", "application/json"}, {"user-agent", client.user_agent}]
      |> maybe_add_header("content-type", content_type)
      |> maybe_add_header("authorization", token && "Bearer #{token}")

    timeout_ms = client.timeout_ms || @default_timeout_ms

    request = %{
      method: opts.method,
      url: url,
      headers: headers,
      body: body,
      timeout_ms: timeout_ms
    }

    client.logger.(
      :debug,
      "Monzo #{opts.method |> Atom.to_string() |> String.upcase()} #{opts.path}"
    )

    case Adapter.dispatch(client.adapter, request) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        decode_response_body(response)

      {:ok, response} ->
        {:error, build_api_error(opts, response)}

      {:error, {:timeout, _reason}} ->
        {:error, %TimeoutError{path: opts.path, timeout_ms: timeout_ms}}

      {:error, reason} ->
        {:error, %NetworkError{path: opts.path, reason: reason}}
    end
  end

  defp maybe_add_header(headers, _name, nil), do: headers
  defp maybe_add_header(headers, name, value), do: [{name, value} | headers]

  defp build_url(client, opts) do
    query = encode_query(opts.query)
    base = client.base_url <> opts.path
    if query == "", do: base, else: base <> "?" <> query
  end

  defp encode_query(query) when query == %{} or query == [], do: ""

  defp encode_query(query) do
    query
    |> Enum.flat_map(fn
      {_key, nil} -> []
      {key, values} when is_list(values) -> Enum.map(values, &{query_key(key), &1})
      {key, value} -> [{query_key(key), value}]
    end)
    |> Enum.map_join("&", fn {key, value} ->
      "#{uri_encode(key)}=#{uri_encode(to_string(value))}"
    end)
  end

  defp query_key(key) when is_atom(key), do: Atom.to_string(key)
  defp query_key(key), do: to_string(key)

  defp uri_encode(value), do: URI.encode_www_form(value)

  defp encode_body(%{encoding: :none}), do: {nil, nil}

  defp encode_body(%{encoding: :form, form: form}) do
    body =
      form
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.map_join("&", fn {k, v} ->
        "#{uri_encode(to_string(k))}=#{uri_encode(to_string(v))}"
      end)

    {"application/x-www-form-urlencoded", body}
  end

  defp encode_body(%{encoding: :json, json: json}) do
    {:ok, body} = JSON.encode(json)
    {"application/json", body}
  end

  defp decode_response_body(%{body: ""}), do: {:ok, %{}}

  defp decode_response_body(%{body: body}) do
    case JSON.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:ok, %{}}
    end
  end

  defp build_api_error(opts, response) do
    parsed =
      case JSON.decode(response.body) do
        {:ok, decoded} when is_map(decoded) -> decoded
        _ -> %{}
      end

    %APIError{
      status: response.status,
      method: opts.method |> Atom.to_string() |> String.upcase(),
      path: opts.path,
      code: parsed["code"] || parsed["error"],
      message: parsed["error_description"] || parsed["message"],
      request_id:
        find_header(response.headers, "x-request-id") ||
          find_header(response.headers, "x-monzo-request-id"),
      params: parsed["params"]
    }
  end

  defp find_header(headers, name) do
    Enum.find_value(headers, fn {k, v} -> if String.downcase(k) == name, do: v end)
  end

  @doc false
  @spec default_timeout_ms() :: pos_integer()
  def default_timeout_ms, do: @default_timeout_ms

  @doc false
  @spec default_retry_policy() :: %{
          max_retries: non_neg_integer(),
          base_delay_ms: pos_integer(),
          max_delay_ms: pos_integer()
        }
  def default_retry_policy do
    %{
      max_retries: @default_max_retries,
      base_delay_ms: @default_base_delay_ms,
      max_delay_ms: @default_max_delay_ms
    }
  end
end
