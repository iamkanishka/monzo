defmodule Monzo.Internal.Path do
  @moduledoc false
  # Internal helper for percent-encoding a value for use as a single URL
  # path segment. `URI.encode_www_form/1` is NOT correct for this - it
  # encodes spaces as `+`, which is only valid in a query string or
  # form body, not a path segment (where `+` is a literal plus sign).

  @spec encode_segment(String.t()) :: String.t()
  def encode_segment(value) do
    URI.encode(value, &URI.char_unreserved?/1)
  end
end
