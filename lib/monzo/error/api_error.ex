defmodule Monzo.Error.APIError do
  @moduledoc """
  Raised/returned for any non-2xx HTTP response from the Monzo API.

  Carries the HTTP status, the parsed error body (if any), and the
  originating request id for support tickets.
  """

  defexception [
    :status,
    :method,
    :path,
    :code,
    :message,
    :request_id,
    :params
  ]

  @type t :: %__MODULE__{
          status: pos_integer(),
          method: String.t(),
          path: String.t(),
          code: String.t() | nil,
          message: String.t() | nil,
          request_id: String.t() | nil,
          params: %{optional(String.t()) => String.t()} | nil
        }

  @impl true
  def message(%__MODULE__{} = error) do
    detail = error.message || error.code || "unknown error"
    "Monzo API error (#{error.status} on #{error.method} #{error.path}): #{detail}"
  end

  @doc "True for 401 responses where the access token is invalid or expired."
  @spec invalid_token?(t()) :: boolean()
  def invalid_token?(%__MODULE__{status: 401}), do: true
  def invalid_token?(%__MODULE__{code: "invalid_token"}), do: true
  def invalid_token?(%__MODULE__{}), do: false

  @doc "True for 403 permission errors."
  @spec forbidden?(t()) :: boolean()
  def forbidden?(%__MODULE__{status: 403}), do: true
  def forbidden?(%__MODULE__{}), do: false

  @doc "True when the client is being rate limited (429)."
  @spec rate_limited?(t()) :: boolean()
  def rate_limited?(%__MODULE__{status: 429}), do: true
  def rate_limited?(%__MODULE__{}), do: false

  @doc "True for 5xx errors, generally safe to retry."
  @spec server_error?(t()) :: boolean()
  def server_error?(%__MODULE__{status: status}), do: status >= 500

  @doc "True when the error represents a transient condition safe to retry for idempotent requests."
  @spec retryable?(t()) :: boolean()
  def retryable?(%__MODULE__{} = error), do: rate_limited?(error) or server_error?(error)
end
