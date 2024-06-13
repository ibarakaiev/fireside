defmodule FiresideTest do
  use ExUnit.Case
  doctest Fireside

  test "greets the world" do
    assert Fireside.hello() == :world
  end
end
