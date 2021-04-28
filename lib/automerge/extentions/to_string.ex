import Kernel, except: [to_string: 1]

defimpl String.Chars, for: Automerge.Text do
  def to_string(text) do
    length =
      if map_size(text._elems) > 0 do
        map_size(text._elems) - 1
      else
        0
      end

    for index <- 0..length, reduce: "" do
      acc ->
        val = Map.get(text._elems, index)

        if is_struct(val.value) or is_nil(val.value) do
          acc
        else
          acc <> val.value
        end
    end
  end
end

defimpl String.Chars, for: Automerge.Text.Elem do
  def to_string(elem) do
    if is_struct(elem.value) or is_nil(elem.value) do
      ""
    else
      elem.value
    end
  end
end
