defmodule Monzo.Balance do
  @moduledoc "Balance information for a Monzo account."

  @type t :: %__MODULE__{
          balance: integer(),
          total_balance: integer(),
          currency: String.t(),
          spend_today: integer()
        }

  defstruct [:balance, :total_balance, :currency, :spend_today]

  @doc false
  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      balance: json["balance"],
      total_balance: json["total_balance"],
      currency: json["currency"],
      spend_today: json["spend_today"]
    }
  end
end
