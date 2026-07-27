defmodule Monzo.Test.MockAdapter do
  @moduledoc """
  A `Monzo.HTTP.Adapter` test double: returns a queued sequence of
  responses (one per call) and records every request it received, via an
  Agent.

  The agent's pid is threaded explicitly through `Monzo.Client`'s
  `{module, opts}` adapter shape (`{Monzo.Test.MockAdapter, agent}`)
  rather than any process-dictionary or application-global state, so it
  works correctly across the process boundaries that `Monzo.HTTP`'s retry
  loop and `Monzo.TokenStore`'s refresh call introduce.

  This plays the same role Bypass would (recording + scripting HTTP
  responses for tests), without requiring a dependency this sandbox can't
  fetch from hex.pm.
  """

  @behaviour Monzo.HTTP.Adapter

  use Agent

  @type responder :: (-> {:ok, Monzo.HTTP.Adapter.response()} | {:error, term()})

  @spec start_link([responder()]) :: Agent.on_start()
  def start_link(responders) do
    Agent.start_link(fn -> %{responders: responders, index: 0, requests: []} end)
  end

  @doc "Builds the `{module, opts}` adapter tuple to pass to `Monzo.Client.new/1`."
  @spec adapter(pid()) :: {module(), pid()}
  def adapter(agent), do: {__MODULE__, agent}

  @impl true
  def request(req, agent) do
    {responder, index} =
      Agent.get_and_update(agent, fn state ->
        responder = Enum.at(state.responders, state.index)
        new_state = %{state | index: state.index + 1, requests: state.requests ++ [req]}
        {{responder, state.index}, new_state}
      end)

    case responder do
      nil -> raise "Monzo.Test.MockAdapter: more calls made (#{index + 1}) than responders queued"
      responder -> responder.()
    end
  end

  @doc "Returns every request the adapter has received so far, in order."
  @spec requests(pid()) :: [Monzo.HTTP.Adapter.request()]
  def requests(agent), do: Agent.get(agent, & &1.requests)

  @doc "Returns how many requests the adapter has received so far."
  @spec call_count(pid()) :: non_neg_integer()
  def call_count(agent), do: agent |> requests() |> length()

  @doc "Builds a responder returning a JSON response with the given status (default 200)."
  @spec json_response(term()) :: responder()
  @spec json_response(pos_integer(), term()) :: responder()
  def json_response(body), do: json_response(200, body)

  def json_response(status, body) do
    fn ->
      {:ok, body} = Monzo.JSON.encode(body)
      {:ok, %{status: status, headers: [{"content-type", "application/json"}], body: body}}
    end
  end

  @doc "Builds a responder returning an empty response with the given status (default 200)."
  @spec empty_response(pos_integer()) :: responder()
  def empty_response(status \\ 200) do
    fn -> {:ok, %{status: status, headers: [], body: ""}} end
  end

  @doc "Builds a responder returning a network-level error."
  @spec error_response(term()) :: responder()
  def error_response(reason) do
    fn -> {:error, reason} end
  end

  @doc "Builds a responder returning a timeout error."
  @spec timeout_response() :: responder()
  def timeout_response do
    fn -> {:error, {:timeout, :timeout}} end
  end
end
