defmodule MapSplice do
  @moduledoc false
  def splice(list, start, value) when is_list(value) do
    splice(list, start, 0, value)
  end

  def splice(list, start, delete_count) when is_number(delete_count) do
    splice(list, start, delete_count, %{})
  end

  def splice(list, start, delete_count, value) when is_map(list) do
    start_range = 0..(start - 1)
    beginning = start + delete_count
    stop = beginning..Enum.count(list)

    enum =
      list
      |> Enum.sort_by(fn {key, _val} -> key end)
      |> Enum.map(fn {_key, value} -> value end)

    if start > 0 do
      Enum.slice(enum, start_range)
    else
      []
    end
    |> Kernel.++(Enum.map(value, fn {_key, value} -> value end))
    |> Kernel.++(Enum.slice(enum, stop))
    |> Enum.with_index()
    |> Enum.map(fn {value, key} -> {key, value} end)
    |> Enum.into(%{})
  end
end
