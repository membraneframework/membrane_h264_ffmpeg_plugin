defmodule TranscodingTest do
  use ExUnit.Case
  import Membrane.Testing.Assertions
  alias Membrane.H264
  alias Membrane.Testing.Pipeline

  defp prepare_paths(filename) do
    in_path = "../fixtures/input-#{filename}.h264" |> Path.expand(__DIR__)
    out_path = "/tmp/output-transcode-#{filename}.h264"
    File.rm(out_path)
    on_exit(fn -> File.rm(out_path) end)
    {in_path, out_path}
  end

  defp make_pipeline(in_path, out_path) do
    Pipeline.start_link(%Pipeline.Options{
      elements: [
        file_src: %Membrane.File.Source{chunk_size: 40_960, location: in_path},
        parser: H264.FFmpeg.Parser,
        decoder: H264.FFmpeg.Decoder,
        encoder: %H264.FFmpeg.Encoder{preset: :fast, crf: 30},
        sink: %Membrane.File.Sink{location: out_path}
      ]
    })
  end

  defp perform_test(filename, timeout) do
    {in_path, out_path} = prepare_paths(filename)

    assert {:ok, pid} = make_pipeline(in_path, out_path)
    assert Pipeline.play(pid) == :ok
    assert_end_of_stream(pid, :sink, :input, timeout)

    Pipeline.stop_and_terminate(pid, blocking?: true)
  end

  describe "TranscodingPipeline should" do
    test "transcode 10 720p frames" do
      perform_test("10-720p", 1000)
    end

    test "transcode 100 240p frames" do
      perform_test("100-240p", 2000)
    end

    test "transcode 20 360p frames with 422 subsampling" do
      perform_test("20-360p-I422", 2000)
    end
  end
end
