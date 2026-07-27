defmodule Monzo.Security do
  @moduledoc """
  Small, dependency-free cryptographic helpers used by the OAuth2 flow:
  CSRF state token generation and constant-time comparison.
  """

  @doc """
  Returns a cryptographically random, URL-safe string suitable for use as
  the OAuth2 `state` parameter to protect against CSRF.
  """
  @spec generate_state(pos_integer()) :: String.t()
  def generate_state(byte_length \\ 32) do
    byte_length
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Compares two strings in constant time, for safely comparing a returned
  OAuth `state` value against the one you generated.
  """
  @spec constant_time_equal?(String.t(), String.t()) :: boolean()
  def constant_time_equal?(a, b) when is_binary(a) and is_binary(b) do
    if byte_size(a) == byte_size(b) do
      :crypto.hash_equals(a, b)
    else
      false
    end
  end
end
