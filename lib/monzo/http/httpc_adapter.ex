defmodule Monzo.HTTP.HttpcAdapter do
  @moduledoc """
  Default Monzo.HTTP.Adapter implementation, built on Erlang's `:httpc`.

  Requires the `:inets` and `:ssl` applications (both part of a standard
  Erlang/OTP install) to be started, which Monzo.Application ensures.
  """

  @behaviour Monzo.HTTP.Adapter

  @impl true
  def request(
        %{method: method, url: url, headers: headers, body: body, timeout_ms: timeout_ms},
        _opts
      ) do
    erl_url = String.to_charlist(url)

    erl_headers =
      Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    http_opts = [timeout: timeout_ms, connect_timeout: timeout_ms]
    opts = [body_format: :binary]

    result =
      case {method, body} do
        {:get, _} ->
          :httpc.request(:get, {erl_url, erl_headers}, http_opts, opts)

        {:delete, nil} ->
          :httpc.request(:delete, {erl_url, erl_headers}, http_opts, opts)

        {method, body} ->
          content_type = content_type_of(headers)
          body = body || ""
          :httpc.request(method, {erl_url, erl_headers, content_type, body}, http_opts, opts)
      end

    case result do
      {:ok, {{_http_version, status, _reason_phrase}, resp_headers, resp_body}} ->
        {:ok,
         %{
           status: status,
           headers: Enum.map(resp_headers, fn {k, v} -> {to_string(k), to_string(v)} end),
           body: to_string(resp_body)
         }}

      {:error, {:failed_connect, _} = reason} ->
        {:error, reason}

      {:error, :timeout} ->
        {:error, {:timeout, :timeout}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp content_type_of(headers) do
    headers
    |> Enum.find_value(~c"application/octet-stream", fn {k, v} ->
      if String.downcase(k) == "content-type", do: String.to_charlist(v)
    end)
  end
end
