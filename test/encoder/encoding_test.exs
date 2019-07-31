defmodule DecodingTest do
  import Membrane.Testing.Assertions
  alias Membrane.Testing.Pipeline
  alias Membrane.Element
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
        file_src: %Element.File.Source{chunk_size: 40_960, location: in_path},
        parser: %Element.RawVideo.Parser{width: width, height: height, format: format},
        encoder: %Element.FFmpeg.H264.Encoder{preset: :fast, crf: 30},
        sink: %Element.File.Sink{location: out_path}
      ],
      links: %{
        {:file_src, :output} => {:parser, :input},
        {:parser, :output} => {:encoder, :input},
        {:encoder, :output} => {:sink, :input}
      }
    })
  end

  describe "EncodingPipeline should" do
    test "encode 10 720p frames" do
      {in_path, out_path} = prepare_paths("10-720p")

      assert {:ok, pid} = make_pipeline(in_path, out_path, 1280, 720)
      assert Pipeline.play(pid) == :ok
      assert_end_of_stream(pid, :sink, :input, 1000)
    end

    test "encode 100 240p frames" do
      {in_path, out_path} = prepare_paths("100-240p")

      assert {:ok, pid} = make_pipeline(in_path, out_path, 320, 240)
      assert Pipeline.play(pid) == :ok
      assert_end_of_stream(pid, :sink, :input, 1000)
    end

    test "encode 20 360p frames with 422 subsampling" do
      {in_path, out_path} = prepare_paths("20-360p-I422")

      assert {:ok, pid} = make_pipeline(in_path, out_path, 480, 360, :I422)
      assert Pipeline.play(pid) == :ok
      assert_end_of_stream(pid, :sink, :input, 1000)
    end
  end
end
