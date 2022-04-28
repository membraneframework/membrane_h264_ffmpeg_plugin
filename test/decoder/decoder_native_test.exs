defmodule Decoder.NativeTest do
  use ExUnit.Case, async: true
  alias Membrane.H264.FFmpeg.Decoder.Native
  alias Membrane.Payload

  test "Decode 1 240p frame" do
    in_path = "../fixtures/input-100-240p.h264" |> Path.expand(__DIR__)
    ref_path = "../fixtures/reference-100-240p.raw" |> Path.expand(__DIR__)

    assert {:ok, file} = File.read(in_path)
    assert {:ok, decoder_ref} = Native.create()
    assert <<frame::bytes-size(7469), _rest::binary>> = file
    assert {:ok, _pts_list, _frames} = Native.decode(frame, 0, 0, false, decoder_ref)
    assert {:ok, _pts_list, [frame]} = Native.flush(false, decoder_ref)
    assert Payload.size(frame) == 115_200
    assert {:ok, ref_file} = File.read(ref_path)
    assert <<ref_frame::bytes-size(115_200), _rest::binary>> = ref_file
    assert Payload.to_binary(frame) == ref_frame
  end
end
