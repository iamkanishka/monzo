defmodule Monzo.SecurityTest do
  use ExUnit.Case, async: true

  alias Monzo.Security

  test "generate_state/1 produces distinct, URL-safe values" do
    a = Security.generate_state()
    b = Security.generate_state()

    assert a != b
    assert a =~ ~r/^[A-Za-z0-9_-]+$/
    assert String.length(a) > 20
  end

  test "generate_state/1 respects byte_length" do
    short = Security.generate_state(8)
    long = Security.generate_state(64)
    assert String.length(long) > String.length(short)
  end

  test "constant_time_equal?/2 correctly compares equal and unequal strings" do
    assert Security.constant_time_equal?("abc", "abc")
    refute Security.constant_time_equal?("abc", "abd")
    refute Security.constant_time_equal?("abc", "abcd")
    assert Security.constant_time_equal?("", "")
  end
end
