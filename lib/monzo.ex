defmodule Monzo do
  @moduledoc """
  A complete, production-grade Elixir client for the [Monzo API](https://docs.monzo.com).

  `monzo` has zero required dependencies - it's built entirely on
  `:inets`/`:httpc`, `:ssl`, and `:crypto` (all part of a standard
  Erlang/OTP install) plus a small vendored JSON codec, so it never forces
  a version choice on your `Jason`, `Req`, `Finch`, or `Tesla` dependencies.

  ## Quickstart

      client = Monzo.Client.new(
        access_token: System.fetch_env!("MONZO_ACCESS_TOKEN"),
        refresh_token: System.fetch_env!("MONZO_REFRESH_TOKEN"),
        client_id: System.fetch_env!("MONZO_CLIENT_ID"),
        client_secret: System.fetch_env!("MONZO_CLIENT_SECRET")
      )

      {:ok, accounts} = Monzo.Accounts.list(client)
      {:ok, balance} = Monzo.Balances.read(client, hd(accounts).id)

  See the `Monzo.Client` and `Monzo.Auth` docs for authenticating, and each
  resource module (`Monzo.Accounts`, `Monzo.Balances`, `Monzo.Pots`,
  `Monzo.Transactions`, `Monzo.FeedItems`, `Monzo.Attachments`,
  `Monzo.Receipts`, `Monzo.Webhooks`) for everything else.

  > #### Scope {: .info}
  >
  > The Monzo API is intended for personal use or a small, explicitly
  > allowed set of users - not for public multi-tenant applications. See
  > [Monzo's docs](https://docs.monzo.com/#acceptable-use-policy).
  """
end
