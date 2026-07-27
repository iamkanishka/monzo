defmodule Monzo.JSONTest do
  use ExUnit.Case, async: true

  alias Monzo.JSON

  describe "encode/1" do
    test "encodes primitives" do
      assert JSON.encode(nil) == {:ok, "null"}
      assert JSON.encode(true) == {:ok, "true"}
      assert JSON.encode(false) == {:ok, "false"}
      assert JSON.encode(42) == {:ok, "42"}
      assert JSON.encode(-7) == {:ok, "-7"}
      assert JSON.encode("hello") == {:ok, "\"hello\""}
    end

    test "encodes floats" do
      assert {:ok, encoded} = JSON.encode(1.5)
      assert String.to_float(encoded) == 1.5
    end

    test "escapes special characters in strings" do
      assert JSON.encode("a\"b") == {:ok, "\"a\\\"b\""}
      assert JSON.encode("a\\b") == {:ok, "\"a\\\\b\""}
      assert JSON.encode("a\nb") == {:ok, "\"a\\nb\""}
      assert JSON.encode("a\tb") == {:ok, "\"a\\tb\""}
    end

    test "encodes lists" do
      assert JSON.encode([1, 2, 3]) == {:ok, "[1,2,3]"}
      assert JSON.encode([]) == {:ok, "[]"}
      assert JSON.encode(["a", "b"]) == {:ok, "[\"a\",\"b\"]"}
    end

    test "encodes maps with atom or string keys" do
      assert {:ok, encoded} = JSON.encode(%{"a" => 1, "b" => 2})
      assert {:ok, decoded} = JSON.decode(encoded)
      assert decoded == %{"a" => 1, "b" => 2}

      assert {:ok, encoded} = JSON.encode(%{a: 1, b: 2})
      assert {:ok, decoded} = JSON.decode(encoded)
      assert decoded == %{"a" => 1, "b" => 2}
    end

    test "encodes nested structures" do
      value = %{"items" => [%{"name" => "x", "amount" => 100}], "total" => 100}
      assert {:ok, encoded} = JSON.encode(value)
      assert {:ok, decoded} = JSON.decode(encoded)
      assert decoded == value
    end

    test "encodes structs by dropping __struct__" do
      assert {:ok, encoded} =
               JSON.encode(%Monzo.Balance{
                 balance: 100,
                 total_balance: 100,
                 currency: "GBP",
                 spend_today: 0
               })

      assert {:ok, decoded} = JSON.decode(encoded)

      assert decoded == %{
               "balance" => 100,
               "total_balance" => 100,
               "currency" => "GBP",
               "spend_today" => 0
             }
    end
  end

  describe "decode/1" do
    test "decodes primitives" do
      assert JSON.decode("null") == {:ok, nil}
      assert JSON.decode("true") == {:ok, true}
      assert JSON.decode("false") == {:ok, false}
      assert JSON.decode("42") == {:ok, 42}
      assert JSON.decode("-42") == {:ok, -42}
      assert JSON.decode("\"hello\"") == {:ok, "hello"}
    end

    test "decodes floats including exponents" do
      assert JSON.decode("1.5") == {:ok, 1.5}
      assert {:ok, value} = JSON.decode("1e10")
      assert value == 1.0e10
    end

    test "decodes escaped strings" do
      assert JSON.decode(~s("a\\"b")) == {:ok, "a\"b"}
      assert JSON.decode(~s("a\\nb")) == {:ok, "a\nb"}
      assert JSON.decode(~s("a\\u00e9b")) == {:ok, "a\u00e9b"}
    end

    test "decodes empty objects and arrays" do
      assert JSON.decode("{}") == {:ok, %{}}
      assert JSON.decode("[]") == {:ok, []}
    end

    test "decodes nested objects and arrays" do
      json = ~s({"accounts":[{"id":"acc_1","description":"Main"}],"count":1})
      assert {:ok, decoded} = JSON.decode(json)

      assert decoded == %{
               "accounts" => [%{"id" => "acc_1", "description" => "Main"}],
               "count" => 1
             }
    end

    test "tolerates whitespace" do
      assert JSON.decode("  { \"a\" : 1 }  ") == {:ok, %{"a" => 1}}
    end

    test "returns an error for invalid JSON" do
      assert {:error, _reason} = JSON.decode("not json")
      assert {:error, _reason} = JSON.decode("{")
      assert {:error, _reason} = JSON.decode(~s({"a":}))
    end

    test "returns an error for trailing data" do
      assert {:error, {:trailing_data, _}} = JSON.decode(~s({"a":1} extra))
    end
  end

  describe "round-trips" do
    test "encode then decode returns an equivalent structure" do
      original = %{
        "id" => "tx_1",
        "amount" => -350,
        "settled" => "",
        "metadata" => %{},
        "merchant" => nil,
        "tags" => ["a", "b", "c"],
        "float" => 12.34
      }

      assert {:ok, encoded} = JSON.encode(original)
      assert {:ok, decoded} = JSON.decode(encoded)
      assert decoded == original
    end
  end

  describe "decode!/1 and encode!/1" do
    test "decode! returns the value directly" do
      assert JSON.decode!(~s({"a":1})) == %{"a" => 1}
    end

    test "decode! raises on invalid input" do
      assert_raise ArgumentError, fn -> JSON.decode!("not json") end
    end
  end
end
