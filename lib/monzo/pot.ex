defmodule Monzo.Pot do
  @moduledoc "A Monzo savings pot attached to a current account."

  alias Monzo.Internal.Time, as: InternalTime

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          style: String.t(),
          balance: integer(),
          currency: String.t(),
          created: DateTime.t() | nil,
          updated: DateTime.t() | nil,
          deleted: boolean()
        }

  defstruct [:id, :name, :style, :balance, :currency, :created, :updated, deleted: false]

  @doc false
  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      id: json["id"],
      name: json["name"],
      style: json["style"],
      balance: json["balance"],
      currency: json["currency"],
      created: InternalTime.parse(json["created"]),
      updated: InternalTime.parse(json["updated"]),
      deleted: json["deleted"] || false
    }
  end
end
