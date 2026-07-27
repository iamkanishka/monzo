defmodule Monzo.Internal.Time do
  @moduledoc false
  # Internal helper for parsing Monzo's RFC3339 timestamps, tolerating the
  # empty string Monzo uses for `settled` on unsettled transactions.

  @spec parse(String.t() | nil) :: DateTime.t() | nil
  def parse(nil), do: nil
  def parse(""), do: nil

  def parse(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  @spec format(DateTime.t() | nil) :: String.t()
  def format(nil), do: ""
  def format(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
