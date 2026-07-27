# Monzo

[![Hex.pm](https://img.shields.io/badge/hex-monzo-blue)](https://hex.pm/packages/monzo)

A complete, production-grade Elixir client for the [Monzo API](https://docs.monzo.com).

- **Full API coverage** — OAuth2, Accounts, Balance, Pots, Transactions, Feed Items, Attachments, Transaction Receipts, Webhooks
- **Zero required dependencies** — built entirely on `:inets`/`:httpc`, `:ssl`, and `:crypto` (all part of a standard Erlang/OTP install) plus a small vendored JSON codec, so it never forces a version choice on your `Jason`, `Req`, `Finch`, or `Tesla` dependencies
- **OTP-native token lifecycle** — a supervised `GenServer` (`Monzo.TokenStore`) owns the mutable access/refresh token pair; `Monzo.Client` itself stays an immutable, shareable struct
- **Resilient by default** — jittered exponential-backoff retries on transient errors, automatic token refresh on `401`s
- **Idiomatic Elixir** — `{:ok, result} | {:error, exception}` everywhere, a lazy `Stream`-based paginator, full `@spec`/`@type` coverage, `mix format`-clean

> **Note on scope**: the Monzo API is intended for personal use or a small, explicitly-allowed set of users — not for public multi-tenant applications. See [Monzo's docs](https://docs.monzo.com/#acceptable-use-policy) for details.

## Installation

```elixir
def deps do
  [
    {:monzo, "~> 1.0"}
  ]
end
```

Requires Elixir ~> 1.14. No other dependencies required.

## Quickstart

```elixir
client = Monzo.Client.new(
  access_token: System.fetch_env!("MONZO_ACCESS_TOKEN"),
  refresh_token: System.fetch_env!("MONZO_REFRESH_TOKEN"),
  client_id: System.fetch_env!("MONZO_CLIENT_ID"),
  client_secret: System.fetch_env!("MONZO_CLIENT_SECRET")
)

{:ok, accounts} = Monzo.Accounts.list(client)
{:ok, balance} = Monzo.Balances.read(client, hd(accounts).id)

IO.puts("Balance: #{balance.balance / 100} #{balance.currency}")
```

## The OAuth2 flow

Monzo access tokens come from a standard OAuth2 authorization-code flow, with one wrinkle: the
token you get back is **not usable until the user approves it inside the Monzo app** (a push
notification + PIN/biometric prompt). Calls fail with `403` until that happens.

```elixir
client = Monzo.Client.new(client_id: client_id, client_secret: client_secret)

# 1. Send the user to Monzo. Persist `state` (e.g. a signed session) to verify on callback.
state = Monzo.Security.generate_state()
{:ok, url} = Monzo.Auth.build_authorization_url(%{
  client_id: client_id,
  redirect_uri: "https://yourapp.com/oauth/callback",
  state: state
})
# redirect the user's browser to `url`

# 2. In your callback handler, verify `state` matches (Monzo.Security.constant_time_equal?/2), then:
{:ok, token} = Monzo.Auth.exchange_code(client, %{
  client_id: client_id,
  client_secret: client_secret,
  redirect_uri: "https://yourapp.com/oauth/callback",
  code: code
})
Monzo.Client.set_tokens(client, token.access_token, token.refresh_token)

# 3. Tell the user to check their phone and approve access in the Monzo app.
```

### Automatic token refresh

Construct the client with `:refresh_token` + `:client_id` + `:client_secret` and it will
transparently refresh an expired access token on a `401` and retry the original request once - no
extra code needed. Use `:on_refresh` to persist rotated tokens (Monzo refresh tokens are
single-use):

```elixir
client = Monzo.Client.new(
  access_token: user.access_token,
  refresh_token: user.refresh_token,
  client_id: client_id,
  client_secret: client_secret,
  on_refresh: fn access_token, refresh_token ->
    MyApp.Users.update_tokens(user.id, access_token, refresh_token)
  end
)
```

## Usage examples

### Pots

```elixir
{:ok, pots} = Monzo.Pots.list(client, account_id)

{:ok, _pot} = Monzo.Pots.deposit(client, %{
  pot_id: hd(pots).id,
  amount: 5_000, # minor units - 5000 = £50.00
  dedupe_id: "deposit-#{order_id}", # keep static across retries of the same logical transfer
  source_account_id: account_id
})
```

### Transactions

```elixir
# A single page
{:ok, transactions} = Monzo.Transactions.list(client, %{account_id: account_id, limit: 50})

# A specific transaction, with merchant expanded inline
{:ok, tx} = Monzo.Transactions.retrieve(client, %{transaction_id: "tx_00008zIcpb1TB4yfVsE6EY", expand: [:merchant]})

# Every transaction, lazily paginated as a Stream
client
|> Monzo.Transactions.stream(%{account_id: account_id})
|> Enum.each(fn tx -> IO.puts("#{tx.created} #{tx.amount} #{tx.description}") end)

# Or lazily take just the first 10:
first_ten = client |> Monzo.Transactions.stream(%{account_id: account_id}) |> Enum.take(10)

# Annotate with custom metadata (empty string deletes a key)
{:ok, tx} = Monzo.Transactions.annotate(client, %{
  transaction_id: tx.id,
  metadata: %{"my_app_category" => "business_expense"}
})
```

> **Full-history sync window**: Monzo only allows fetching a user's complete transaction history
> during the first 5 minutes after authentication. After that, only the last 90 days are
> available. If you need full history, run your `stream/2` backfill immediately after the OAuth
> callback completes.

### Attachments

```elixir
{:ok, %{upload_url: upload_url, file_url: file_url}} = Monzo.Attachments.request_upload(client, %{
  file_name: "receipt.jpg", file_type: "image/jpeg", content_length: byte_size(file_bytes)
})

:ok = Monzo.Attachments.upload_bytes(client, upload_url, file_bytes, "image/jpeg")

{:ok, attachment} = Monzo.Attachments.register(client, %{
  external_id: tx.id, file_url: file_url, file_type: "image/jpeg"
})
```

### Transaction receipts

Unlike the rest of the API, this endpoint takes a JSON body. `external_id` is your own idempotency
key - calling `create/2` again with the same `external_id` updates the receipt.

```elixir
{:ok, receipt_id} = Monzo.Receipts.create(client, %Monzo.Receipt{
  external_id: "order-#{order_id}",
  transaction_id: tx.id,
  total: 1299,
  currency: "GBP",
  items: [%Monzo.Receipt.Item{description: "Flat White", quantity: 1, amount: 1299, currency: "GBP"}]
})
```

### Webhooks

```elixir
{:ok, webhook} = Monzo.Webhooks.register(client, account_id, "https://yourapp.com/hooks/monzo")
```

Handling an inbound webhook (e.g. in a Phoenix controller):

```elixir
def handle_webhook(conn, _params) do
  {:ok, raw_body, conn} = Plug.Conn.read_body(conn)

  with {:ok, event} <- Monzo.Webhooks.parse_event(raw_body),
       :ok <- Monzo.Webhooks.assert_expected_account(event, [expected_account_id]) do
    if event.type == "transaction.created" do
      Logger.info("New transaction: #{event.data.id} #{event.data.amount}")
    end

    send_resp(conn, 200, "")
  else
    {:error, _reason} -> send_resp(conn, 400, "")
  end
end
```

> **On webhook security**: as of this writing, Monzo does not document a cryptographic signature
> (HMAC or similar) on webhook deliveries, so `parse_event/1` cannot verify authenticity beyond
> shape-checking the payload. Serve your endpoint over HTTPS, treat the URL as a secret, validate
> the account id against an allow-list (as above), and re-fetch anything financially sensitive via
> `Monzo.Transactions.retrieve/2` rather than trusting the webhook body outright.

## Error handling

Every error the SDK returns is a proper `Exception` struct, returned as `{:error, exception}`
(functions never raise for expected API/validation failures - only for genuine bugs):

```elixir
case Monzo.Pots.withdraw(client, params) do
  {:ok, pot} ->
    pot

  {:error, %Monzo.Error.APIError{} = error} ->
    cond do
      Monzo.Error.APIError.rate_limited?(error) -> :backoff
      Monzo.Error.APIError.forbidden?(error) -> :token_not_yet_approved
      true -> Logger.error("Monzo API error: #{Exception.message(error)}")
    end

  {:error, %Monzo.Error.ValidationError{} = error} ->
    # invalid arguments caught client-side before any request was sent
    Logger.error(Exception.message(error))

  {:error, %Monzo.Error.TimeoutError{}} ->
    :timed_out
end
```

## Configuration reference

```elixir
Monzo.Client.new(
  base_url: url,                    # default: "https://api.monzo.com"
  adapter: module_or_tuple,         # default: Monzo.HTTP.HttpcAdapter
  timeout_ms: ms,                   # default: 15_000
  retry: %{max_retries: 2, base_delay_ms: 250, max_delay_ms: 4_000},
  logger: fn level, message -> ... end,
  user_agent: "my-app/1.0",
  access_token: token,
  refresh_token: token,
  client_id: id,
  client_secret: secret,
  on_refresh: fn access, refresh -> ... end,
  token_store: pid_or_name          # reuse an already-running Monzo.TokenStore
)
```

### Custom HTTP adapters

`Monzo.HTTP.HttpcAdapter` (built on `:httpc`) is the default and requires no extra dependencies.
To use a connection-pooled client like Finch instead, implement the `Monzo.HTTP.Adapter`
behaviour and pass it (optionally as `{MyAdapter, opts}` if it needs configuration) via
`:adapter`.

## Development

```bash
mix deps.get      # fetches ex_doc/dialyxir/credo/excoveralls (dev/test only, not required at runtime)
mix compile
mix test
mix format --check-formatted
mix credo --strict
mix dialyzer
```

> This package was originally built in a network-sandboxed environment without access to
> `repo.hex.pm`, so its dev-only tooling deps are commented out in `mix.exs` by default - on a
> machine with normal Hex access, uncomment them and run `mix deps.get`.

## License

MIT
