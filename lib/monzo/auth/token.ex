defmodule Monzo.Auth.Token do
  @moduledoc "The response returned by Monzo's token endpoint."

  @type t :: %__MODULE__{
          access_token: String.t(),
          client_id: String.t() | nil,
          expires_in: integer() | nil,
          refresh_token: String.t() | nil,
          token_type: String.t() | nil,
          user_id: String.t() | nil,
          obtained_at: DateTime.t()
        }

  defstruct [
    :access_token,
    :client_id,
    :expires_in,
    :refresh_token,
    :token_type,
    :user_id,
    :obtained_at
  ]

  @doc false
  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      access_token: json["access_token"],
      client_id: json["client_id"],
      expires_in: json["expires_in"],
      refresh_token: json["refresh_token"],
      token_type: json["token_type"],
      user_id: json["user_id"],
      obtained_at: DateTime.utc_now()
    }
  end

  @doc "Returns the wall-clock time this token expires at."
  @spec expires_at(t()) :: DateTime.t() | nil
  def expires_at(%__MODULE__{expires_in: nil}), do: nil

  def expires_at(%__MODULE__{obtained_at: obtained_at, expires_in: expires_in}) do
    DateTime.add(obtained_at, expires_in, :second)
  end

  @doc """
  Returns whether the token is expired as of now, with `margin_seconds`
  subtracted from the expiry to account for clock skew and in-flight requests.
  """
  @spec expired?(t(), non_neg_integer()) :: boolean()
  def expired?(%__MODULE__{} = token, margin_seconds \\ 0) do
    case expires_at(token) do
      nil ->
        false

      expires_at ->
        DateTime.compare(DateTime.add(DateTime.utc_now(), margin_seconds, :second), expires_at) !=
          :lt
    end
  end
end
