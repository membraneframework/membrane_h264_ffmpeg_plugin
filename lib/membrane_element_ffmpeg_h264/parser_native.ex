defmodule Membrane.Element.FFmpeg.H264.Parser.Native do
  use Unifex.Loader

  def foo(pframes, input) do
    Enum.map_reduce(pframes, input, fn size, stream ->
      <<frame::bytes-size(size), rest::binary>> = stream
      {frame, rest}
    end)
  end
end
