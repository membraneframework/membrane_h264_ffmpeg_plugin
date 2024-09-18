defmodule Encoder.NativeTest do
  use ExUnit.Case, async: true

  import Membrane.Time

  alias Membrane.H264.FFmpeg.Common
  alias Membrane.H264.FFmpeg.Encoder.Native, as: Enc

  test "Encode 1 240p frame" do
    in_path = "../fixtures/reference-100-240p.raw" |> Path.expand(__DIR__)

    assert {:ok, file} = File.read(in_path)
    assert {:ok, ref} = Enc.create(320, 240, :I420, :fast, nil, :high, -1, -1, 1, 1, 23, 40, [])
    assert <<frame::bytes-size(115_200), _tail::binary>> = file

    Enum.each(
      0..5,
      fn timestamp ->
        assert {:ok, [], [], []} ==
                 Enc.encode(
                   frame,
                   Common.to_h264_time_base_truncated(seconds(timestamp)),
                   _use_shm? = false,
                   _keyframe_requested? = false,
                   ref
                 )
      end
    )

    assert {:ok, dts_list, pts_list, frames} = Enc.flush(false, ref)
    assert Enum.all?([dts_list, pts_list, frames], &(length(&1) == 6))

    expected_timestamps = Enum.map(0..5, &Common.to_h264_time_base_truncated(seconds(&1)))

    assert Enum.sort(pts_list) == expected_timestamps
  end
end
