defmodule Monzo.Attachments do
  @moduledoc """
  The Attachments resource: the three-step flow of requesting an upload
  URL, uploading raw bytes to storage, and registering the file against a
  transaction.
  """

  alias Monzo.Attachment
  alias Monzo.Client
  alias Monzo.Error.{NetworkError, ValidationError}
  alias Monzo.HTTP

  @type upload_params :: %{
          required(:file_name) => String.t(),
          required(:file_type) => String.t(),
          required(:content_length) => non_neg_integer()
        }
  @type upload_result :: %{file_url: String.t(), upload_url: String.t()}

  @doc """
  Step 1: obtains a temporary, pre-signed URL to upload the attachment to,
  and the resulting public URL of the file once uploaded.
  """
  @spec request_upload(Client.t(), upload_params()) ::
          {:ok, upload_result()} | {:error, Exception.t()}
  def request_upload(%Client{} = client, %{
        file_name: file_name,
        file_type: file_type,
        content_length: content_length
      })
      when is_binary(file_name) and file_name != "" and content_length > 0 do
    form = %{
      "file_name" => file_name,
      "file_type" => file_type,
      "content_length" => content_length
    }

    request =
      HTTP.request(client,
        method: :post,
        path: "/attachment/upload",
        encoding: :form,
        form: form,
        idempotent: false
      )

    with {:ok, json} <- request do
      {:ok, %{file_url: json["file_url"], upload_url: json["upload_url"]}}
    end
  end

  def request_upload(%Client{}, _params) do
    {:error,
     %ValidationError{
       field: :file_name,
       message: "file_name must not be empty and content_length must be positive"
     }}
  end

  @doc """
  Step 2: uploads raw file bytes directly to a pre-signed URL returned by
  `request_upload/2`. This talks directly to Monzo's file storage, not the
  Monzo API, so it does not use the client's bearer auth or retry policy.
  """
  @spec upload_bytes(Client.t(), String.t(), iodata(), String.t()) ::
          :ok | {:error, Exception.t()}
  def upload_bytes(
        %Client{adapter: adapter, timeout_ms: timeout_ms},
        upload_url,
        content,
        content_type
      ) do
    request = %{
      method: :put,
      url: upload_url,
      headers: [{"content-type", content_type}],
      body: IO.iodata_to_binary(content),
      timeout_ms: timeout_ms || HTTP.default_timeout_ms()
    }

    case HTTP.Adapter.dispatch(adapter, request) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status}} ->
        {:error, %NetworkError{path: upload_url, reason: {:unexpected_status, status}}}

      {:error, reason} ->
        {:error, %NetworkError{path: upload_url, reason: reason}}
    end
  end

  @type register_params :: %{
          required(:external_id) => String.t(),
          required(:file_url) => String.t(),
          required(:file_type) => String.t()
        }

  @doc """
  Step 3: registers a `file_url` (from `request_upload/2`, or an
  externally-hosted image) against a transaction so it appears in the
  Monzo app's transaction detail screen.
  """
  @spec register(Client.t(), register_params()) ::
          {:ok, Attachment.t()} | {:error, Exception.t()}
  def register(%Client{} = client, %{
        external_id: external_id,
        file_url: file_url,
        file_type: file_type
      })
      when is_binary(external_id) and external_id != "" and is_binary(file_url) and file_url != "" do
    form = %{"external_id" => external_id, "file_url" => file_url, "file_type" => file_type}

    request =
      HTTP.request(client,
        method: :post,
        path: "/attachment/register",
        encoding: :form,
        form: form,
        idempotent: false
      )

    with {:ok, %{"attachment" => json}} <- request do
      {:ok, Attachment.from_json(json)}
    end
  end

  def register(%Client{}, _params) do
    {:error,
     %ValidationError{field: :external_id, message: "external_id and file_url must not be empty"}}
  end

  @doc "Removes a previously registered attachment."
  @spec deregister(Client.t(), String.t()) :: :ok | {:error, Exception.t()}
  def deregister(%Client{} = client, attachment_id)
      when is_binary(attachment_id) and attachment_id != "" do
    request =
      HTTP.request(client,
        method: :post,
        path: "/attachment/deregister",
        encoding: :form,
        form: %{"id" => attachment_id},
        idempotent: false
      )

    case request do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  def deregister(%Client{}, _attachment_id) do
    {:error, %ValidationError{field: :attachment_id, message: "must not be empty"}}
  end
end
