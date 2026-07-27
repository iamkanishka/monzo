defmodule Monzo.Merchant do
  @moduledoc "Merchant details for a transaction, present when expanded."

  alias Monzo.Internal.Time, as: InternalTime

  defmodule Address do
    @moduledoc "Physical address of a transaction's merchant."

    @type t :: %__MODULE__{
            address: String.t() | nil,
            city: String.t() | nil,
            country: String.t() | nil,
            latitude: float() | nil,
            longitude: float() | nil,
            postcode: String.t() | nil,
            region: String.t() | nil
          }

    defstruct [:address, :city, :country, :latitude, :longitude, :postcode, :region]

    @doc false
    @spec from_json(map() | nil) :: t() | nil
    def from_json(nil), do: nil

    def from_json(json) do
      %__MODULE__{
        address: json["address"],
        city: json["city"],
        country: json["country"],
        latitude: json["latitude"],
        longitude: json["longitude"],
        postcode: json["postcode"],
        region: json["region"]
      }
    end
  end

  @type t :: %__MODULE__{
          id: String.t(),
          group_id: String.t() | nil,
          name: String.t(),
          logo: String.t() | nil,
          emoji: String.t() | nil,
          category: String.t() | nil,
          address: Address.t() | nil,
          created: DateTime.t() | nil
        }

  defstruct [:id, :group_id, :name, :logo, :emoji, :category, :address, :created]

  @doc false
  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      id: json["id"],
      group_id: json["group_id"],
      name: json["name"],
      logo: json["logo"],
      emoji: json["emoji"],
      category: json["category"],
      address: Address.from_json(json["address"]),
      created: InternalTime.parse(json["created"])
    }
  end
end
