defmodule Monzo.FeedItemsTest do
  use ExUnit.Case, async: true

  alias Monzo.Test.MockAdapter

  defp client(agent) do
    Monzo.Client.new(
      base_url: "https://api.monzo.com",
      adapter: MockAdapter.adapter(agent),
      access_token: "t"
    )
  end

  test "create/2 posts a basic feed item" do
    {:ok, agent} = MockAdapter.start_link([MockAdapter.empty_response()])

    assert :ok =
             Monzo.FeedItems.create(client(agent), %{
               account_id: "acc_1",
               type: :basic,
               params: %{title: "Hello", image_url: "https://x.com/i.png", body: "World"},
               url: "https://x.com"
             })

    [req] = MockAdapter.requests(agent)
    decoded = URI.decode_query(req.body)
    assert decoded["account_id"] == "acc_1"
    assert decoded["params[title]"] == "Hello"
    assert decoded["params[image_url]"] == "https://x.com/i.png"
  end

  test "create/2 rejects missing title" do
    {:ok, agent} = MockAdapter.start_link([])

    assert {:error, %Monzo.Error.ValidationError{field: :title}} =
             Monzo.FeedItems.create(client(agent), %{
               account_id: "acc_1",
               type: :basic,
               params: %{title: "", image_url: "https://x.com/i.png"}
             })
  end
end
