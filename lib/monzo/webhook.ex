defmodule Monzo.Webhook do
  @moduledoc "A registered callback URL for an account."

  defmodule Event do
    @moduledoc "An inbound webhook delivery."

    @type t :: %__MODULE__{
            type: String.t(),
            data: Monzo.Transaction.t()
          }

    defstruct [:type, :data]
  end

  @type t :: %__MODULE__{
          id: String.t(),
          account_id: String.t(),
          url: String.t()
        }

  defstruct [:id, :account_id, :url]

  @doc false
  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{id: json["id"], account_id: json["account_id"], url: json["url"]}
  end
end
