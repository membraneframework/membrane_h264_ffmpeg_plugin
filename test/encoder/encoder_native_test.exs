defmodule Encoder.NativeTest do
  use ExUnit.Case, async: true
  alias Membrane.H264.FFmpeg.Encoder.Native, as: Enc

  test "Encode 1 240p frame" do
    in_path = "../fixtures/reference-100-240p.raw" |> Path.expand(__DIR__)

    assert {:ok, file} = File.read(in_path)
    assert {:ok, ref} = Enc.create(320, 240, :I420, :fast, :high, 30, 1, 23)
    assert <<frame::bytes-size(115_200), tail::binary>> = file
    assert {:ok, frames} = Enc.encode(frame, ref)
    assert {:ok, [frame]} = Enc.flush(ref)
  end
end
