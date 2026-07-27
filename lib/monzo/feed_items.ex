defmodule Monzo.FeedItems do
  @moduledoc "The Feed Items resource: posting items to a user's Monzo feed."

  alias Monzo.Client
  alias Monzo.Error.ValidationError

  @type basic_params :: %{
          required(:title) => String.t(),
          required(:image_url) => String.t(),
          optional(:body) => String.t(),
          optional(:background_color) => String.t(),
          optional(:title_color) => String.t(),
          optional(:body_color) => String.t()
        }

  @type create_params :: %{
          required(:account_id) => String.t(),
          required(:type) => :basic,
          required(:params) => basic_params(),
          optional(:url) => String.t()
        }

  @doc """
  Creates a new dismissible feed item on the user's feed. Currently only
  the `:basic` type (image + title + optional body) is supported by Monzo.

      Monzo.FeedItems.create(client, %{
        account_id: account_id,
        type: :basic,
        params: %{title: "Order shipped!", image_url: "https://example.com/icon.png"}
      })
  """
  @spec create(Client.t(), create_params()) :: :ok | {:error, Exception.t()}
  def create(
        %Client{} = client,
        %{account_id: account_id, type: :basic, params: item_params} = params
      )
      when is_binary(account_id) and account_id != "" do
    with :ok <- validate_present(:title, item_params[:title]),
         :ok <- validate_present(:image_url, item_params[:image_url]) do
      form = %{
        "account_id" => account_id,
        "type" => "basic",
        "url" => params[:url],
        "params[title]" => item_params[:title],
        "params[image_url]" => item_params[:image_url],
        "params[body]" => item_params[:body],
        "params[background_color]" => item_params[:background_color],
        "params[title_color]" => item_params[:title_color],
        "params[body_color]" => item_params[:body_color]
      }

      case Monzo.HTTP.request(client,
             method: :post,
             path: "/feed",
             encoding: :form,
             form: form,
             idempotent: false
           ) do
        {:ok, _} -> :ok
        {:error, _} = error -> error
      end
    end
  end

  def create(%Client{}, _params) do
    {:error, %ValidationError{field: :account_id, message: "must not be empty"}}
  end

  defp validate_present(_field, value) when is_binary(value) and value != "", do: :ok

  defp validate_present(field, _value),
    do: {:error, %ValidationError{field: field, message: "must not be empty"}}
end
