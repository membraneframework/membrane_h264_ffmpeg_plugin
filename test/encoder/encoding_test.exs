defmodule DecodingTest do
  import Membrane.Testing.Assertions
  alias Membrane.Element
  alias Membrane.H264
  alias Membrane.Testing.Pipeline
  use ExUnit.Case

  def prepare_paths(filename) do
    in_path = "../fixtures/reference-#{filename}.raw" |> Path.expand(__DIR__)
    out_path = "/tmp/output-encode-#{filename}.h264"
    File.rm(out_path)
    on_exit(fn -> File.rm(out_path) end)
    {in_path, out_path}
  end

  def make_pipeline(in_path, out_path, width, height, format \\ :I420) do
    Pipeline.start_link(%Pipeline.Options{
      elements: [
        file_src: %Membrane.File.Source{chunk_size: 40_960, location: in_path},
        parser: %Element.RawVideo.Parser{width: width, height: height, format: format},
        encoder: %H264.FFmpeg.Encoder{preset: :fast, crf: 30},
        sink: %Membrane.File.Sink{location: out_path}
      ]
    })
  end

  def perform_test(filename, width, height, format \\ :I420) do
    {in_path, out_path} = prepare_paths(filename)

    assert {:ok, pid} = make_pipeline(in_path, out_path, width, height, format)
    assert Pipeline.play(pid) == :ok
    assert_end_of_stream(pid, :sink, :input, 3000)

    Pipeline.stop_and_terminate(pid, blocking?: true)
  end

  describe "EncodingPipeline should" do
    test "encode 10 720p frames" do
      perform_test("10-720p", 1280, 720)
    end

    test "encode 100 240p frames" do
      perform_test("100-240p", 340, 240)
    end

    test "encode 20 360p frames with 422 subsampling" do
      perform_test("20-360p-I422", 480, 360, :I422)
    end
  end
end
