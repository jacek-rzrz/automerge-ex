defimpl Enumerable, for: Automerge.Text do
  def count(%Automerge.Text{_elems: elems}) do
    {:ok, map_size(elems)}
  end

  def member?(%Automerge.Text{_elems: elems}, {key, value}) do
    {:ok, match?(%{^key => ^value}, elems)}
  end

  def member?(_map, _other) do
    {:ok, false}
  end

  def slice(%Automerge.Text{_elems: elems}) do
    size = map_size(elems)
    {:ok, size, &Enumerable.List.slice(:maps.to_list(elems), &1, &2, size)}
  end

  def reduce(%Automerge.Text{_elems: elems}, acc, fun) do
    Enumerable.List.reduce(:maps.to_list(elems), acc, fun)
  end
end

defimpl Enumerable, for: Automerge.List do
  def count(%Automerge.List{_value: value}) do
    {:ok, map_size(value)}
  end

  def member?(%Automerge.List{_value: value}, {key, value}) do
    {:ok, match?(%{^key => ^value}, value)}
  end

  def member?(_map, _other) do
    {:ok, false}
  end

  def slice(%Automerge.List{_value: value}) do
    size = map_size(value)

    range_end =
      if size > 0 do
        size - 1
      else
        0
      end

    list =
      if size > 0 do
        for index <- 0..range_end, reduce: [] do
          acc ->
            val = Map.get(value, index)

            List.insert_at(acc, index, val)
        end
      else
        []
      end

    {:ok, size, &Enumerable.List.slice(list, &1, &2, size)}
  end

  def reduce(%Automerge.List{_value: value}, acc, fun) do
    size = map_size(value)

    range_end =
      if size > 0 do
        size - 1
      else
        0
      end

    list =
      if size > 0 do
        for index <- 0..range_end, reduce: [] do
          acc ->
            val = Map.get(value, index)

            List.insert_at(acc, index, val)
        end
      else
        []
      end

    Enumerable.List.reduce(list, acc, fun)
  end
end

defimpl Enumerable, for: Automerge.Map do
  def count(%Automerge.Map{_value: value}) do
    {:ok, map_size(value)}
  end

  def member?(%Automerge.Map{_value: value}, {key, value}) do
    {:ok, match?(%{^key => ^value}, value)}
  end

  def member?(_map, _other) do
    {:ok, false}
  end

  def slice(%Automerge.Map{_value: value}) do
    size = map_size(value)
    {:ok, size, &Enumerable.List.slice(:maps.to_list(value), &1, &2, size)}
  end

  def reduce(%Automerge.Map{_value: value}, acc, fun) do
    Enumerable.List.reduce(:maps.to_list(value), acc, fun)
  end
end
