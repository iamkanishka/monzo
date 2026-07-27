defmodule Monzo.Account do
  @moduledoc "A Monzo current account."

  alias Monzo.Internal.Time, as: InternalTime

  @type t :: %__MODULE__{
          id: String.t(),
          description: String.t(),
          created: DateTime.t() | nil
        }

  defstruct [:id, :description, :created]

  @doc false
  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      id: json["id"],
      description: json["description"],
      created: InternalTime.parse(json["created"])
    }
  end
end
