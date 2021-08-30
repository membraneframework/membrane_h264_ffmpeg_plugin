defmodule Parser.NativeTest do
  use ExUnit.Case, async: true
  alias Membrane.H264.FFmpeg.Parser.Native, as: Parser

  test "Decode 1 240p frame" do
    in_path = "../fixtures/input-100-240p.h264" |> Path.expand(__DIR__)

    assert {:ok, file} = File.read(in_path)
    assert {:ok, decoder_ref} = Parser.create()
    assert <<frame::bytes-size(7469), _::binary>> = file
    assert {:ok, _frames, _change_idx} = Parser.parse(frame, decoder_ref)
    assert {:ok, [7469]} = Parser.flush(decoder_ref)
  end
end
