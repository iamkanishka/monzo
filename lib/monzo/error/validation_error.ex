defmodule Monzo.Error.ValidationError do
  @moduledoc "Raised for invalid SDK usage caught client-side, before any request is sent."

  defexception [:field, :message]

  @type t :: %__MODULE__{field: atom() | String.t(), message: String.t()}

  @impl true
  def message(%__MODULE__{field: field, message: message}) do
    "Monzo validation error on #{inspect(field)}: #{message}"
  end
end
