# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - Unreleased

### Added

- Initial release of `monzo`.
- Full OAuth2 authorization-code flow: `Monzo.Auth.build_authorization_url/1`,
  `exchange_code/2`, `refresh_token/2`, `logout/1`, `who_am_i/1`.
- `Monzo.Client` (immutable config struct) + `Monzo.TokenStore` (supervised
  `GenServer`) for automatic access-token refresh on 401, with a
  configurable `:on_refresh` persistence hook.
- Resource modules for the full Monzo API surface: `Monzo.Accounts`,
  `Monzo.Balances`, `Monzo.Pots`, `Monzo.Transactions` (including a lazy
  `Stream`-based `stream/2` for full-history pagination), `Monzo.FeedItems`,
  `Monzo.Attachments`, `Monzo.Receipts`, `Monzo.Webhooks`.
- Typed exception hierarchy (`Monzo.Error.APIError`, `TimeoutError`,
  `NetworkError`, `ValidationError`, `WebhookVerificationError`).
- Automatic exponential-backoff retries with jitter for transient
  (429/5xx/network) failures on idempotent requests.
- `Monzo.Webhooks.parse_event/1` / `assert_expected_account/2` helpers for
  safely handling inbound webhooks.
- Zero required dependencies - built entirely on `:inets`/`:httpc`, `:ssl`,
  `:crypto`, and a vendored `Monzo.JSON` codec.
