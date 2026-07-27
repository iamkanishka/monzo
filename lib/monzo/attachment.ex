defmodule Monzo.Attachment do
  @moduledoc "A file registered against a transaction."

  alias Monzo.Internal.Time, as: InternalTime

  @type t :: %__MODULE__{
          id: String.t(),
          user_id: String.t() | nil,
          external_id: String.t(),
          file_url: String.t(),
          file_type: String.t(),
          created: DateTime.t() | nil
        }

  defstruct [:id, :user_id, :external_id, :file_url, :file_type, :created]

  @doc false
  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      id: json["id"],
      user_id: json["user_id"],
      external_id: json["external_id"],
      file_url: json["file_url"],
      file_type: json["file_type"],
      created: InternalTime.parse(json["created"])
    }
  end
end
