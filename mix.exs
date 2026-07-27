defmodule Monzo.MixProject do
  use Mix.Project

  @source_url "https://github.com/iamkanishka/monzo"
  @version "1.0.0"

  def project do
    [
      app: :monzo,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: description(),
      package: package(),
      name: "Monzo",
      source_url: @source_url,
      docs: docs(),
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        flags: [:error_handling, :unmatched_returns]
      ],
      test_coverage: [tool: :cover]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl, :crypto],
      mod: {Monzo.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      # monzo has zero required runtime dependencies - it is built entirely
      # on :inets/:httpc, :ssl, and :crypto plus a small vendored JSON codec
      # (Monzo.JSON), so it never conflicts with a host application's Jason,
      # Req, Finch, or Tesla choices.
      #
      # The following are optional, dev/test-only tooling. They're commented
      # out here because this package was built in a sandboxed environment
      # without access to repo.hex.pm - uncomment them for local development
      # (`mix deps.get` will fetch them normally on a machine with Hex access).
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp description do
    "A complete, production-grade Elixir client for the Monzo API: OAuth2, " <>
      "Accounts, Balance, Pots, Transactions, Feed Items, Attachments, " <>
      "Transaction Receipts, and Webhooks. Zero required dependencies."
  end

  defp package do
    [
      name: "monzo",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      source_ref: "v#{@version}",
      source_url: @source_url,
      groups_for_modules: [
        Resources: [
          Monzo.Auth,
          Monzo.Accounts,
          Monzo.Balance,
          Monzo.Pots,
          Monzo.Transactions,
          Monzo.FeedItems,
          Monzo.Attachments,
          Monzo.Receipts,
          Monzo.Webhooks
        ],
        Entities: [
          Monzo.Account,
          Monzo.Balance.Amount,
          Monzo.Pot,
          Monzo.Transaction,
          Monzo.Merchant,
          Monzo.Attachment,
          Monzo.Receipt,
          Monzo.Webhook,
          Monzo.Webhook.Event
        ],
        Errors: [
          Monzo.Error.APIError,
          Monzo.Error.TimeoutError,
          Monzo.Error.NetworkError,
          Monzo.Error.ValidationError,
          Monzo.Error.WebhookVerificationError
        ],
        Internals: [
          Monzo.Client,
          Monzo.TokenStore,
          Monzo.HTTP,
          Monzo.HTTP.Adapter,
          Monzo.HTTP.HttpcAdapter,
          Monzo.JSON,
          Monzo.Pagination,
          Monzo.Security
        ]
      ]
    ]
  end
end
