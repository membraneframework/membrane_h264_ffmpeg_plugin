defmodule Encoder.NativeTest do
  use ExUnit.Case, async: true

  import Membrane.Time

  alias Membrane.H264.FFmpeg.Common
  alias Membrane.H264.FFmpeg.Encoder.Native, as: Enc

  test "Encode 1 240p frame" do
    in_path = "../fixtures/reference-100-240p.raw" |> Path.expand(__DIR__)

    assert {:ok, file} = File.read(in_path)
    assert {:ok, ref} = Enc.create(320, 240, :I420, :fast, :high, -1, -1, 1, 1, 23)
    assert <<frame::bytes-size(115_200), _tail::binary>> = file

    Enum.each(
      0..4,
      &Enc.encode(frame, Common.to_h264_time_base_truncated(seconds(&1)), false, ref)
    )

    assert {:ok, _dts_list, _pts, _frames} =
             Enc.encode(frame, Common.to_h264_time_base_truncated(seconds(5)), false, ref)

    assert {:ok, _dts, pts, _frames} = Enc.flush(false, ref)

    assert Enum.sort(Enum.map(pts, &Common.to_membrane_time_base_truncated(&1))) ==
             Enum.map(0..5, &seconds(&1))
  end
end
