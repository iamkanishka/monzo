defmodule Monzo.Error.NetworkError do
  @moduledoc "Raised for network-level failures (DNS, connection refused, etc)."

  defexception [:path, :reason]

  @type t :: %__MODULE__{path: String.t(), reason: term()}

  @impl true
  def message(%__MODULE__{path: path, reason: reason}) do
    "Monzo network error while calling #{path}: #{inspect(reason)}"
  end
end
