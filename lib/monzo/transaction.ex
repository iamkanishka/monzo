defmodule Monzo.Transaction do
  @moduledoc """
  A single ledger entry on a Monzo account.

  The `merchant` field is polymorphic on the wire: it's a bare merchant id
  string unless expanded via `expand: [:merchant]`, in which case it's a
  full object. This struct always splits that into two separate fields:
  `merchant_id` (always present when a merchant exists) and `merchant`
  (only populated when expanded).
  """

  alias Monzo.Internal.Time, as: InternalTime

  @type decline_reason ::
          :insufficient_funds | :card_inactive | :card_blocked | :invalid_cvc | :other | nil

  @type t :: %__MODULE__{
          id: String.t(),
          amount: integer(),
          created: DateTime.t() | nil,
          currency: String.t(),
          description: String.t(),
          metadata: %{optional(String.t()) => String.t()},
          notes: String.t(),
          is_load: boolean(),
          settled: DateTime.t() | nil,
          category: String.t() | nil,
          decline_reason: decline_reason(),
          account_id: String.t() | nil,
          merchant_id: String.t() | nil,
          merchant: Monzo.Merchant.t() | nil
        }

  defstruct [
    :id,
    :amount,
    :created,
    :currency,
    :description,
    :notes,
    :settled,
    :category,
    :decline_reason,
    :account_id,
    :merchant_id,
    :merchant,
    metadata: %{},
    is_load: false
  ]

  @doc false
  @spec from_json(map()) :: t()
  def from_json(json) do
    {merchant_id, merchant} = parse_merchant(json["merchant"])

    %__MODULE__{
      id: json["id"],
      amount: json["amount"],
      created: InternalTime.parse(json["created"]),
      currency: json["currency"],
      description: json["description"],
      metadata: json["metadata"] || %{},
      notes: json["notes"] || "",
      is_load: json["is_load"] || false,
      settled: InternalTime.parse(json["settled"]),
      category: json["category"],
      decline_reason: parse_decline_reason(json["decline_reason"]),
      account_id: json["account_id"],
      merchant_id: merchant_id,
      merchant: merchant
    }
  end

  defp parse_merchant(nil), do: {nil, nil}
  defp parse_merchant(id) when is_binary(id), do: {id, nil}

  defp parse_merchant(%{} = merchant_json) do
    merchant = Monzo.Merchant.from_json(merchant_json)
    {merchant.id, merchant}
  end

  defp parse_decline_reason(nil), do: nil
  defp parse_decline_reason("INSUFFICIENT_FUNDS"), do: :insufficient_funds
  defp parse_decline_reason("CARD_INACTIVE"), do: :card_inactive
  defp parse_decline_reason("CARD_BLOCKED"), do: :card_blocked
  defp parse_decline_reason("INVALID_CVC"), do: :invalid_cvc
  defp parse_decline_reason(_other), do: :other

  @doc "Returns the RFC3339 cursor value used for pagination (the transaction's `created` timestamp)."
  @spec cursor_value(t()) :: String.t() | nil
  def cursor_value(%__MODULE__{created: nil}), do: nil
  def cursor_value(%__MODULE__{created: created}), do: DateTime.to_iso8601(created)
end
