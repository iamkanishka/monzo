defmodule Monzo.Error.TimeoutError do
  @moduledoc "Raised when a request exceeds the configured timeout."

  defexception [:path, :timeout_ms]

  @type t :: %__MODULE__{path: String.t(), timeout_ms: pos_integer()}

  @impl true
  def message(%__MODULE__{path: path, timeout_ms: timeout_ms}) do
    "Monzo request to #{path} timed out after #{timeout_ms}ms"
  end
end
