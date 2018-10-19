defmodule Decoder.NativeTest do
  use ExUnit.Case, async: true
  alias Membrane.Payload
  alias Membrane.Element.FFmpeg.H264.Decoder.Native, as: Dec

  test "Decode 1 240p frame" do
    in_path = "fixtures/input-100-240p.h264" |> Path.expand(__DIR__)
    ref_path = "fixtures/reference-100-240p.raw" |> Path.expand(__DIR__)

    assert {:ok, file} = File.read(in_path)
    assert {:ok, decoder_ref} = Dec.create()
    assert <<frame::bytes-size(7469), _::binary>> = file
    assert {:ok, frames} = Dec.decode(frame, decoder_ref)
    assert {:ok, [frame]} = Dec.flush(decoder_ref)
    assert Payload.size(frame) == 115_200
    assert {:ok, ref_file} = File.read(ref_path)
    assert <<ref_frame::bytes-size(115_200), _::binary>> = ref_file
    assert Payload.to_binary(frame) == ref_frame
  end
end
