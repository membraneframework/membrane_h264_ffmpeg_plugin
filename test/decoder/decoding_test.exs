defmodule DecoderTest do
  use ExUnit.Case
  use Membrane.Pipeline

  import Membrane.Testing.Assertions

  alias Membrane.H264
  alias Membrane.H264.FFmpeg.Common
  alias Membrane.Testing
  alias Membrane.Testing.Pipeline

  @framerate 30

  defp prepare_paths(filename, tmp_dir) do
    in_path = "../fixtures/input-#{filename}.h264" |> Path.expand(__DIR__)
    reference_path = "../fixtures/reference-#{filename}.raw" |> Path.expand(__DIR__)
    out_path = Path.join(tmp_dir, "output-decoding-#{filename}.raw")
    {in_path, reference_path, out_path}
  end

  defp make_pipeline(in_path, out_path) do
    Pipeline.start_link_supervised!(
      spec:
        child(:file_src, %Membrane.File.Source{chunk_size: 40_960, location: in_path})
        |> child(:parser, H264.Parser)
        |> child(:decoder, H264.FFmpeg.Decoder)
        |> child(:sink, %Membrane.File.Sink{location: out_path})
    )
  end

  defp make_pipeline_with_test_sink(in_path) do
    Pipeline.start_link_supervised!(
      spec:
        child(:file_src, %Membrane.File.Source{chunk_size: 40_960, location: in_path})
        |> child(:parser, %H264.Parser{
          generate_best_effort_timestamps: %{framerate: {@framerate, 1}}
        })
        |> child(:decoder, H264.FFmpeg.Decoder)
        |> child(:sink, Testing.Sink)
    )
  end

  defp assert_files_equal(file_a, file_b) do
    assert {:ok, a} = File.read(file_a)
    assert {:ok, b} = File.read(file_b)
    assert a == b
  end

  defp perform_decoding_test(filename, tmp_dir, timeout) do
    {in_path, ref_path, out_path} = prepare_paths(filename, tmp_dir)

    pid = make_pipeline(in_path, out_path)
    assert_end_of_stream(pid, :sink, :input, timeout)
    assert_files_equal(out_path, ref_path)
    Pipeline.terminate(pid)
  end

  defp perform_timestamping_test(filename, tmp_dir, frame_count) do
    {in_path, _ref_path, _out_path} = prepare_paths(filename, tmp_dir)

    frame_duration = Numbers.div(Membrane.Time.second(), @framerate)

    pid = make_pipeline_with_test_sink(in_path)
    assert_sink_playing(pid, :sink)

    0..(frame_count - 1)
    |> Enum.each(fn i ->
      expected_pts =
        Numbers.mult(i, frame_duration)
        # trunc in parser
        |> Ratio.trunc()
        |> Common.to_h264_time_base_truncated()
        |> Common.to_membrane_time_base_truncated()

      assert_sink_buffer(pid, :sink, %Membrane.Buffer{pts: pts})
      assert expected_pts == pts
    end)

    Pipeline.terminate(pid)
  end

  describe "DecodingPipeline should" do
    @describetag :tmp_dir
    test "decode 10 720p frames", ctx do
      perform_decoding_test("10-720p", ctx.tmp_dir, 500)
    end

    test "decode 100 240p frames", ctx do
      perform_decoding_test("100-240p", ctx.tmp_dir, 1000)
    end

    test "decode 20 360p frames with 422 subsampling", ctx do
      perform_decoding_test("20-360p-I422", ctx.tmp_dir, 1000)
    end

    test "decode 10 720p frames with B frames in main profile", ctx do
      perform_decoding_test("10-720p-main", ctx.tmp_dir, 1000)
    end

    test "append correct timestamps to 10 720p frames", ctx do
      perform_timestamping_test("10-720p-no-b-frames", ctx.tmp_dir, 10)
    end

    test "append correct timestamps to 100 240p frames", ctx do
      perform_timestamping_test("100-240p-no-b-frames", ctx.tmp_dir, 100)
    end
  end
end
