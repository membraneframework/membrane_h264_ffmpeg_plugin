defmodule DecoderTest do
  use ExUnit.Case
  import Membrane.Testing.Assertions
  alias Membrane.H264
  alias Membrane.Testing
  alias Membrane.Testing.Pipeline
  alias Membrane.H264.FFmpeg.Common

  @framerate 30

  defp prepare_paths(filename) do
    in_path = "../fixtures/input-#{filename}.h264" |> Path.expand(__DIR__)
    reference_path = "../fixtures/reference-#{filename}.raw" |> Path.expand(__DIR__)
    out_path = "/tmp/output-decoding-#{filename}.raw"
    File.rm(out_path)
    on_exit(fn -> File.rm(out_path) end)
    {in_path, reference_path, out_path}
  end

  defp make_pipeline(in_path, out_path) do
    Pipeline.start_link(%Pipeline.Options{
      elements: [
        file_src: %Membrane.File.Source{chunk_size: 40_960, location: in_path},
        parser: H264.FFmpeg.Parser,
        decoder: H264.FFmpeg.Decoder,
        sink: %Membrane.File.Sink{location: out_path}
      ]
    })
  end

  defp make_pipeline_with_test_sink(in_path) do
    Pipeline.start_link(%Pipeline.Options{
      elements: [
        file_src: %Membrane.File.Source{chunk_size: 40_960, location: in_path},
        parser: %H264.FFmpeg.Parser{framerate: {@framerate, 1}},
        decoder: H264.FFmpeg.Decoder,
        sink: Testing.Sink
      ]
    })
  end

  defp assert_files_equal(file_a, file_b) do
    assert {:ok, a} = File.read(file_a)
    assert {:ok, b} = File.read(file_b)
    assert a == b
  end

  defp perform_decoding_test(filename, timeout) do
    {in_path, ref_path, out_path} = prepare_paths(filename)

    assert {:ok, pid} = make_pipeline(in_path, out_path)
    assert Pipeline.play(pid) == :ok
    assert_end_of_stream(pid, :sink, :input, timeout)
    assert_files_equal(out_path, ref_path)

    Testing.Pipeline.stop_and_terminate(pid, blocking?: true)
  end

  defp perform_timestamping_test(filename, frame_count) do
    {in_path, _ref_path, _out_path} = prepare_paths(filename)

    frame_duration = Ratio.div(Membrane.Time.second(), @framerate)

    assert {:ok, pid} = make_pipeline_with_test_sink(in_path)
    assert Pipeline.play(pid) == :ok

    0..(frame_count - 1)
    |> Enum.each(fn i ->
      expected_pts =
        Ratio.mult(i, frame_duration)
        # trunc in parser
        |> Ratio.trunc()
        |> Common.to_h264_time_base()
        # trunc before passing time to native decoder
        |> Ratio.trunc()
        |> Common.to_membrane_time_base()
        # trunc after rebasing time to membrane time base
        |> Ratio.trunc()

      assert_sink_buffer(pid, :sink, %Membrane.Buffer{pts: pts})
      assert expected_pts == pts
    end)

    Testing.Pipeline.stop_and_terminate(pid, blocking?: true)
  end

  describe "DecodingPipeline should" do
    test "decode 10 720p frames" do
      perform_decoding_test("10-720p", 500)
    end

    test "decode 100 240p frames" do
      perform_decoding_test("100-240p", 1000)
    end

    test "decode 20 360p frames with 422 subsampling" do
      perform_decoding_test("20-360p-I422", 1000)
    end

    test "decode 10 720p frames with B frames in main profile" do
      perform_decoding_test("10-720p-main", 1000)
    end

    test "append correct timestamps to 10 720p frames" do
      perform_timestamping_test("10-720p-no-b-frames", 10)
    end

    test "append correct timestamps to 100 240p frames" do
      perform_timestamping_test("100-240p-no-b-frames", 100)
    end
  end
end
