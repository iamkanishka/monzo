# Run with: mix run examples/transactions.exs
#
# Requires MONZO_ACCESS_TOKEN (and optionally MONZO_REFRESH_TOKEN,
# MONZO_CLIENT_ID, MONZO_CLIENT_SECRET for automatic refresh) in the
# environment.

client =
  Monzo.Client.new(
    access_token: System.fetch_env!("MONZO_ACCESS_TOKEN"),
    refresh_token: System.get_env("MONZO_REFRESH_TOKEN"),
    client_id: System.get_env("MONZO_CLIENT_ID"),
    client_secret: System.get_env("MONZO_CLIENT_SECRET"),
    on_refresh: fn _access, _refresh -> IO.puts("tokens refreshed") end
  )

{:ok, accounts} = Monzo.Accounts.list(client)

case accounts do
  [] ->
    IO.puts("No accounts found")

  [account | _] ->
    {:ok, balance} = Monzo.Balances.read(client, account.id)
    IO.puts("Balance: #{balance.balance / 100} #{balance.currency}")

    # Walk every transaction for the account, oldest first, one page at a
    # time. Run this immediately after auth if you need full history -
    # Monzo only allows a full backfill in the first 5 minutes post-auth.
    count =
      client
      |> Monzo.Transactions.stream(%{account_id: account.id})
      |> Enum.reduce(0, fn tx, count ->
        IO.puts("#{tx.created} #{Float.round(tx.amount / 100, 2)} #{tx.description}")
        count + 1
      end)

    IO.puts("Total transactions: #{count}")
end
