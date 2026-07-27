# A minimal Plug-based webhook receiver, demonstrating Monzo.Webhooks.parse_event/1
# and assert_expected_account/2. Requires `{:plug_cowboy, "~> 2.0"}` as a
# separate dependency in your own application - this file is illustrative,
# not runnable standalone (monzo itself has no HTTP-server dependency).
#
#   MONZO_ACCESS_TOKEN=... MONZO_ACCOUNT_ID=... mix run examples/webhook.exs

defmodule ExampleWebhookHandler do
  @moduledoc false

  @spec handle(String.t(), [String.t()]) :: :ok | {:error, term()}
  def handle(raw_body, expected_account_ids) do
    with {:ok, event} <- Monzo.Webhooks.parse_event(raw_body),
         :ok <- Monzo.Webhooks.assert_expected_account(event, expected_account_ids) do
      if event.type == "transaction.created" do
        IO.puts("New transaction: #{event.data.id} #{event.data.amount} #{event.data.description}")
      end

      :ok
    end
  end
end

client = Monzo.Client.new(access_token: System.fetch_env!("MONZO_ACCESS_TOKEN"))
account_id = System.fetch_env!("MONZO_ACCOUNT_ID")

{:ok, webhook} = Monzo.Webhooks.register(client, account_id, "https://yourapp.com/hooks/monzo")
IO.puts("Registered webhook #{webhook.id}. Wire ExampleWebhookHandler.handle/2 into your router.")
