defmodule Monzo.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Monzo.TokenStore.Registry},
      {DynamicSupervisor, name: Monzo.TokenStore.Supervisor, strategy: :one_for_one}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Monzo.Supervisor)
  end
end
