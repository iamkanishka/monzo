defmodule Monzo.JSON do
  @moduledoc """
  A small, dependency-free JSON encoder/decoder.

  `monzo` deliberately vendors its own minimal JSON codec rather than
  depending on Jason (or any other library) so that it never forces a
  version choice on a host application. It supports every JSON construct
  needed to talk to the Monzo API: objects, arrays, strings (with unicode
  escapes), numbers, booleans, and null.

  This is not meant to be a general-purpose, maximally-optimised JSON
  library - if your application already depends on Jason, feel free to
  swap it in via a custom `Monzo.HTTP.Adapter` if you need different
  performance characteristics. For typical API payload sizes, this codec
  is more than fast enough.
  """

  @type json ::
          nil | boolean() | number() | String.t() | [json()] | %{optional(String.t()) => json()}

  @doc """
  Encodes an Elixir term to a JSON string.

  Maps, keyword lists (of primitives), lists, strings, numbers, atoms
  (`true`/`false`/`nil`), and any struct implementing `Monzo.JSON.Encoder`
  (or a plain map after `Map.from_struct/1`) are supported.
  """
  @spec encode(term()) :: {:ok, String.t()} | {:error, term()}
  def encode(term) do
    {:ok, IO.iodata_to_binary(encode!(term))}
  rescue
    error -> {:error, error}
  end

  @spec encode!(term()) :: iodata()
  def encode!(nil), do: "null"
  def encode!(true), do: "true"
  def encode!(false), do: "false"
  def encode!(value) when is_atom(value), do: encode_string(Atom.to_string(value))
  def encode!(value) when is_binary(value), do: encode_string(value)
  def encode!(value) when is_integer(value), do: Integer.to_string(value)
  def encode!(value) when is_float(value), do: encode_float(value)

  def encode!(value) when is_list(value) do
    if Keyword.keyword?(value) and value != [] do
      encode_map(Map.new(value))
    else
      ["[", encode_list_items(value), "]"]
    end
  end

  def encode!(%_struct{} = value) do
    value
    |> Map.from_struct()
    |> encode!()
  end

  def encode!(value) when is_map(value), do: encode_map(value)

  defp encode_list_items([]), do: []
  defp encode_list_items([item]), do: encode!(item)

  defp encode_list_items([item | rest]) do
    [encode!(item), "," | encode_list_items(rest)]
  end

  defp encode_map(value) do
    pairs =
      value
      |> Enum.reject(fn {_k, v} -> v == :__json_omit__ end)
      |> Enum.map(fn {k, v} -> [encode_string(to_key(k)), ":", encode!(v)] end)
      |> Enum.intersperse(",")

    ["{", pairs, "}"]
  end

  defp to_key(key) when is_atom(key), do: Atom.to_string(key)
  defp to_key(key) when is_binary(key), do: key
  defp to_key(key), do: to_string(key)

  defp encode_float(value) do
    if value == trunc(value) do
      # Render whole-number floats without a trailing ".0" mismatch risk;
      # Erlang's :erlang.float_to_binary/2 always includes a decimal point.
      :erlang.float_to_binary(value, [:compact, {:decimals, 10}])
    else
      :erlang.float_to_binary(value, [:short])
    end
  end

  defp encode_string(value) do
    [?", escape(value), ?"]
  end

  defp escape(<<>>), do: []

  defp escape(<<?", rest::binary>>), do: [?\\, ?" | escape(rest)]
  defp escape(<<?\\, rest::binary>>), do: [?\\, ?\\ | escape(rest)]
  defp escape(<<?\n, rest::binary>>), do: [?\\, ?n | escape(rest)]
  defp escape(<<?\r, rest::binary>>), do: [?\\, ?r | escape(rest)]
  defp escape(<<?\t, rest::binary>>), do: [?\\, ?t | escape(rest)]

  defp escape(<<c::utf8, rest::binary>>) when c < 0x20 do
    [:io_lib.format("\\u~4.16.0b", [c]) | escape(rest)]
  end

  defp escape(<<c::utf8, rest::binary>>) do
    [<<c::utf8>> | escape(rest)]
  end

  @doc """
  Decodes a JSON string into Elixir terms. Objects become maps with
  string keys, arrays become lists, and numbers become integers or
  floats as appropriate.
  """
  @spec decode(String.t()) :: {:ok, json()} | {:error, term()}
  def decode(binary) when is_binary(binary) do
    case parse_value(skip_whitespace(binary)) do
      {:ok, value, rest} ->
        case skip_whitespace(rest) do
          "" -> {:ok, value}
          _ -> {:error, {:trailing_data, rest}}
        end

      {:error, _} = error ->
        error
    end
  rescue
    error -> {:error, error}
  end

  @spec decode!(String.t()) :: json()
  def decode!(binary) do
    case decode(binary) do
      {:ok, value} -> value
      {:error, reason} -> raise ArgumentError, "invalid JSON: #{inspect(reason)}"
    end
  end

  defp skip_whitespace(<<c, rest::binary>>) when c in [?\s, ?\t, ?\n, ?\r],
    do: skip_whitespace(rest)

  defp skip_whitespace(binary), do: binary

  defp parse_value(<<"null", rest::binary>>), do: {:ok, nil, rest}
  defp parse_value(<<"true", rest::binary>>), do: {:ok, true, rest}
  defp parse_value(<<"false", rest::binary>>), do: {:ok, false, rest}
  defp parse_value(<<?", rest::binary>>), do: parse_string(rest, [])
  defp parse_value(<<?{, rest::binary>>), do: parse_object(skip_whitespace(rest), %{})
  defp parse_value(<<?[, rest::binary>>), do: parse_array(skip_whitespace(rest), [])

  defp parse_value(<<c, _::binary>> = binary) when c in ~c"-0123456789" do
    parse_number(binary)
  end

  defp parse_value(other), do: {:error, {:unexpected_token, other}}

  defp parse_object(<<?}, rest::binary>>, acc), do: {:ok, acc, rest}

  defp parse_object(<<?", rest::binary>>, acc) do
    with {:ok, key, rest} <- parse_string(rest, []),
         rest = skip_whitespace(rest),
         <<?:, rest::binary>> <- rest,
         rest = skip_whitespace(rest),
         {:ok, value, rest} <- parse_value(rest) do
      acc = Map.put(acc, key, value)

      case skip_whitespace(rest) do
        <<?,, rest::binary>> -> parse_object(skip_whitespace(rest), acc)
        <<?}, rest::binary>> -> {:ok, acc, rest}
        other -> {:error, {:expected_comma_or_close_object, other}}
      end
    else
      {:error, _} = error -> error
      other -> {:error, {:invalid_object, other}}
    end
  end

  defp parse_object(other, _acc), do: {:error, {:invalid_object, other}}

  defp parse_array(<<?], rest::binary>>, acc), do: {:ok, Enum.reverse(acc), rest}

  defp parse_array(binary, acc) do
    with {:ok, value, rest} <- parse_value(binary) do
      acc = [value | acc]

      case skip_whitespace(rest) do
        <<?,, rest::binary>> -> parse_array(skip_whitespace(rest), acc)
        <<?], rest::binary>> -> {:ok, Enum.reverse(acc), rest}
        other -> {:error, {:expected_comma_or_close_array, other}}
      end
    end
  end

  defp parse_string(<<?", rest::binary>>, acc) do
    {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp parse_string(<<?\\, ?", rest::binary>>, acc), do: parse_string(rest, [?" | acc])
  defp parse_string(<<?\\, ?\\, rest::binary>>, acc), do: parse_string(rest, [?\\ | acc])
  defp parse_string(<<?\\, ?/, rest::binary>>, acc), do: parse_string(rest, [?/ | acc])
  defp parse_string(<<?\\, ?b, rest::binary>>, acc), do: parse_string(rest, [?\b | acc])
  defp parse_string(<<?\\, ?f, rest::binary>>, acc), do: parse_string(rest, [?\f | acc])
  defp parse_string(<<?\\, ?n, rest::binary>>, acc), do: parse_string(rest, [?\n | acc])
  defp parse_string(<<?\\, ?r, rest::binary>>, acc), do: parse_string(rest, [?\r | acc])
  defp parse_string(<<?\\, ?t, rest::binary>>, acc), do: parse_string(rest, [?\t | acc])

  defp parse_string(<<?\\, ?u, hex::binary-size(4), rest::binary>>, acc) do
    codepoint = String.to_integer(hex, 16)
    parse_string(rest, [<<codepoint::utf8>> | acc])
  end

  defp parse_string(<<c::utf8, rest::binary>>, acc), do: parse_string(rest, [<<c::utf8>> | acc])
  defp parse_string(<<>>, _acc), do: {:error, :unterminated_string}

  defp parse_number(binary) do
    {number_str, rest} = take_number(binary, [])
    text = IO.iodata_to_binary(number_str)

    value =
      if String.contains?(text, ".") or String.contains?(text, "e") or String.contains?(text, "E") do
        String.to_float(normalize_exponent(text))
      else
        String.to_integer(text)
      end

    {:ok, value, rest}
  end

  defp normalize_exponent(text) do
    if String.contains?(text, ".") do
      text
    else
      String.replace(text, ~r/e/i, ".0e")
    end
  end

  defp take_number(<<c, rest::binary>>, acc) when c in ~c"-+0123456789.eE" do
    take_number(rest, [acc, c])
  end

  defp take_number(rest, acc), do: {acc, rest}
end
