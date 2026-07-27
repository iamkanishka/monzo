defmodule Monzo.AttachmentsTest do
  use ExUnit.Case, async: true

  alias Monzo.Test.MockAdapter

  defp client(agent) do
    Monzo.Client.new(
      base_url: "https://api.monzo.com",
      adapter: MockAdapter.adapter(agent),
      access_token: "t"
    )
  end

  test "request_upload/2 obtains an upload URL" do
    {:ok, agent} =
      MockAdapter.start_link([
        MockAdapter.json_response(%{
          "file_url" => "https://s3/x.png",
          "upload_url" => "https://s3-upload/x.png"
        })
      ])

    assert {:ok, %{upload_url: "https://s3-upload/x.png", file_url: "https://s3/x.png"}} =
             Monzo.Attachments.request_upload(client(agent), %{
               file_name: "x.png",
               file_type: "image/png",
               content_length: 100
             })
  end

  test "upload_bytes/4 PUTs raw bytes directly to the pre-signed URL" do
    {:ok, agent} = MockAdapter.start_link([MockAdapter.empty_response()])

    assert :ok =
             Monzo.Attachments.upload_bytes(
               client(agent),
               "https://s3-upload/x.png",
               <<1, 2, 3>>,
               "image/png"
             )

    [req] = MockAdapter.requests(agent)
    assert req.method == :put
    assert req.url == "https://s3-upload/x.png"
    assert {"content-type", "image/png"} in req.headers
  end

  test "upload_bytes/4 returns an error on a non-2xx response" do
    {:ok, agent} = MockAdapter.start_link([MockAdapter.empty_response(500)])

    assert {:error, %Monzo.Error.NetworkError{}} =
             Monzo.Attachments.upload_bytes(
               client(agent),
               "https://s3-upload/x.png",
               <<1>>,
               "image/png"
             )
  end

  test "register/2 associates a file with a transaction" do
    {:ok, agent} =
      MockAdapter.start_link([
        MockAdapter.json_response(%{
          "attachment" => %{
            "id" => "attach_1",
            "user_id" => "user_1",
            "external_id" => "tx_1",
            "file_url" => "https://s3/x.png",
            "file_type" => "image/png",
            "created" => "2020-01-01T00:00:00Z"
          }
        })
      ])

    assert {:ok, attachment} =
             Monzo.Attachments.register(client(agent), %{
               external_id: "tx_1",
               file_url: "https://s3/x.png",
               file_type: "image/png"
             })

    assert attachment.id == "attach_1"
  end

  test "deregister/2 removes an attachment" do
    {:ok, agent} = MockAdapter.start_link([MockAdapter.empty_response()])
    assert :ok = Monzo.Attachments.deregister(client(agent), "attach_1")

    [req] = MockAdapter.requests(agent)
    assert req.body == "id=attach_1"
  end
end
