defmodule Monzo.Auth.WhoAmI do
  @moduledoc "Metadata Monzo returns about the currently configured access token."

  @type t :: %__MODULE__{
          authenticated: boolean(),
          client_id: String.t() | nil,
          user_id: String.t() | nil
        }

  defstruct [:authenticated, :client_id, :user_id]

  @doc false
  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      authenticated: json["authenticated"] || false,
      client_id: json["client_id"],
      user_id: json["user_id"]
    }
  end
end
