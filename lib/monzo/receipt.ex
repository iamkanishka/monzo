defmodule Monzo.Receipt do
  @moduledoc """
  A detailed, itemised receipt attached to a transaction.

  Unlike every other Monzo resource, receipts are sent and received as a
  JSON body rather than form-encoded.
  """

  defmodule SubItem do
    @moduledoc "A nested line item within an `Item` (e.g. modifiers on a dish)."

    @type t :: %__MODULE__{
            description: String.t(),
            quantity: number(),
            unit: String.t() | nil,
            amount: integer(),
            currency: String.t(),
            tax: integer() | nil
          }

    @enforce_keys [:description, :quantity, :amount, :currency]
    defstruct [:description, :quantity, :unit, :amount, :currency, :tax]

    @doc false
    @spec to_json(t()) :: map()
    def to_json(%__MODULE__{} = item) do
      %{
        "description" => item.description,
        "quantity" => item.quantity,
        "unit" => item.unit,
        "amount" => item.amount,
        "currency" => item.currency,
        "tax" => item.tax
      }
    end
  end

  defmodule Item do
    @moduledoc "A single line item on a receipt."

    @type t :: %__MODULE__{
            description: String.t(),
            quantity: number(),
            unit: String.t() | nil,
            amount: integer(),
            currency: String.t(),
            tax: integer() | nil,
            sub_items: [SubItem.t()]
          }

    @enforce_keys [:description, :quantity, :amount, :currency]
    defstruct [:description, :quantity, :unit, :amount, :currency, :tax, sub_items: []]

    @doc false
    @spec to_json(t()) :: map()
    def to_json(%__MODULE__{} = item) do
      %{
        "description" => item.description,
        "quantity" => item.quantity,
        "unit" => item.unit,
        "amount" => item.amount,
        "currency" => item.currency,
        "tax" => item.tax,
        "sub_items" => Enum.map(item.sub_items, &SubItem.to_json/1)
      }
    end
  end

  defmodule Tax do
    @moduledoc "A tax line applied to the receipt as a whole."

    @type t :: %__MODULE__{
            description: String.t(),
            amount: integer(),
            currency: String.t(),
            tax_number: String.t() | nil
          }

    @enforce_keys [:description, :amount, :currency]
    defstruct [:description, :amount, :currency, :tax_number]

    @doc false
    @spec to_json(t()) :: map()
    def to_json(%__MODULE__{} = tax) do
      %{
        "description" => tax.description,
        "amount" => tax.amount,
        "currency" => tax.currency,
        "tax_number" => tax.tax_number
      }
    end
  end

  defmodule Payment do
    @moduledoc "One payment method applied to the receipt."

    @type payment_type :: :card | :cash | :gift_card

    @type t :: %__MODULE__{
            type: payment_type(),
            amount: integer(),
            currency: String.t(),
            bin: String.t() | nil,
            last_four: String.t() | nil,
            auth_code: String.t() | nil,
            aid: String.t() | nil,
            mid: String.t() | nil,
            tid: String.t() | nil,
            gift_card_type: String.t() | nil
          }

    @enforce_keys [:type, :amount, :currency]
    defstruct [
      :type,
      :amount,
      :currency,
      :bin,
      :last_four,
      :auth_code,
      :aid,
      :mid,
      :tid,
      :gift_card_type
    ]

    @doc false
    @spec to_json(t()) :: map()
    def to_json(%__MODULE__{} = payment) do
      %{
        "type" => Atom.to_string(payment.type),
        "amount" => payment.amount,
        "currency" => payment.currency,
        "bin" => payment.bin,
        "last_four" => payment.last_four,
        "auth_code" => payment.auth_code,
        "aid" => payment.aid,
        "mid" => payment.mid,
        "tid" => payment.tid,
        "gift_card_type" => payment.gift_card_type
      }
    end
  end

  defmodule Merchant do
    @moduledoc "Optional merchant metadata for a receipt."

    @type t :: %__MODULE__{
            name: String.t() | nil,
            online: boolean() | nil,
            phone: String.t() | nil,
            email: String.t() | nil,
            store_name: String.t() | nil,
            store_address: String.t() | nil,
            store_postcode: String.t() | nil
          }

    defstruct [:name, :online, :phone, :email, :store_name, :store_address, :store_postcode]

    @doc false
    @spec to_json(t() | nil) :: map() | nil
    def to_json(nil), do: nil

    def to_json(%__MODULE__{} = merchant) do
      %{
        "name" => merchant.name,
        "online" => merchant.online,
        "phone" => merchant.phone,
        "email" => merchant.email,
        "store_name" => merchant.store_name,
        "store_address" => merchant.store_address,
        "store_postcode" => merchant.store_postcode
      }
    end
  end

  @type t :: %__MODULE__{
          id: String.t() | nil,
          external_id: String.t(),
          transaction_id: String.t(),
          total: integer(),
          currency: String.t(),
          items: [Item.t()],
          taxes: [Tax.t()],
          payments: [Payment.t()],
          merchant: Merchant.t() | nil
        }

  @enforce_keys [:external_id, :transaction_id, :total, :currency, :items]
  defstruct [
    :id,
    :external_id,
    :transaction_id,
    :total,
    :currency,
    :merchant,
    items: [],
    taxes: [],
    payments: []
  ]

  @doc false
  @spec to_json(t()) :: map()
  def to_json(%__MODULE__{} = receipt) do
    %{
      "external_id" => receipt.external_id,
      "transaction_id" => receipt.transaction_id,
      "total" => receipt.total,
      "currency" => receipt.currency,
      "items" => Enum.map(receipt.items, &Item.to_json/1),
      "taxes" => Enum.map(receipt.taxes, &Tax.to_json/1),
      "payments" => Enum.map(receipt.payments, &Payment.to_json/1),
      "merchant" => Merchant.to_json(receipt.merchant)
    }
  end

  @doc false
  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      id: json["id"],
      external_id: json["external_id"],
      transaction_id: json["transaction_id"],
      total: json["total"],
      currency: json["currency"],
      items: Enum.map(json["items"] || [], &item_from_json/1),
      taxes: Enum.map(json["taxes"] || [], &tax_from_json/1),
      payments: Enum.map(json["payments"] || [], &payment_from_json/1),
      merchant: merchant_from_json(json["merchant"])
    }
  end

  defp item_from_json(json) do
    %Item{
      description: json["description"],
      quantity: json["quantity"],
      unit: json["unit"],
      amount: json["amount"],
      currency: json["currency"],
      tax: json["tax"],
      sub_items: Enum.map(json["sub_items"] || [], &sub_item_from_json/1)
    }
  end

  defp sub_item_from_json(json) do
    %SubItem{
      description: json["description"],
      quantity: json["quantity"],
      unit: json["unit"],
      amount: json["amount"],
      currency: json["currency"],
      tax: json["tax"]
    }
  end

  defp tax_from_json(json) do
    %Tax{
      description: json["description"],
      amount: json["amount"],
      currency: json["currency"],
      tax_number: json["tax_number"]
    }
  end

  defp payment_from_json(json) do
    %Payment{
      type: payment_type_from_json(json["type"]),
      amount: json["amount"],
      currency: json["currency"],
      bin: json["bin"],
      last_four: json["last_four"],
      auth_code: json["auth_code"],
      aid: json["aid"],
      mid: json["mid"],
      tid: json["tid"],
      gift_card_type: json["gift_card_type"]
    }
  end

  defp payment_type_from_json("card"), do: :card
  defp payment_type_from_json("cash"), do: :cash
  defp payment_type_from_json("gift_card"), do: :gift_card
  defp payment_type_from_json(_other), do: :card

  defp merchant_from_json(nil), do: nil

  defp merchant_from_json(json) do
    %Merchant{
      name: json["name"],
      online: json["online"],
      phone: json["phone"],
      email: json["email"],
      store_name: json["store_name"],
      store_address: json["store_address"],
      store_postcode: json["store_postcode"]
    }
  end
end
