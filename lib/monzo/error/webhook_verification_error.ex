defmodule Monzo.Error.WebhookVerificationError do
  @moduledoc """
  Raised by webhook parsing/verification helpers when a payload cannot be
  trusted (malformed JSON, unexpected shape, or an unexpected account id).
  """

  defexception [:message]

  @type t :: %__MODULE__{message: String.t()}
end
