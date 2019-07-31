defmodule TranscodingTest do
  import Membrane.Testing.Assertions
  alias Membrane.Testing.Pipeline
  alias Membrane.Element
  use ExUnit.Case

  def prepare_paths(filename) do
    in_path = "../fixtures/input-#{filename}.h264" |> Path.expand(__DIR__)
    out_path = "/tmp/output-transcode-#{filename}.h264"
    File.rm(out_path)
    on_exit(fn -> File.rm(out_path) end)
    {in_path, out_path}
  end

  def make_pipeline(in_path, out_path) do
    Pipeline.start_link(%Pipeline.Options{
      elements: [
        file_src: %Element.File.Source{chunk_size: 40_960, location: in_path},
        parser: Element.FFmpeg.H264.Parser,
        decoder: Element.FFmpeg.H264.Decoder,
        encoder: %Element.FFmpeg.H264.Encoder{preset: :fast, crf: 30},
        sink: %Element.File.Sink{location: out_path}
      ],
      links: %{
        {:file_src, :output} => {:parser, :input},
        {:parser, :output} => {:decoder, :input},
        {:decoder, :output} => {:encoder, :input},
        {:encoder, :output} => {:sink, :input}
      }
    })
  end

  describe "TranscodingPipeline should" do
    test "transcode 10 720p frames" do
      {in_path, out_path} = prepare_paths("10-720p")

      assert {:ok, pid} = make_pipeline(in_path, out_path)
      assert Pipeline.play(pid) == :ok
      assert_end_of_stream(pid, :sink, :input, 1000)
    end

    test "transcode 100 240p frames" do
      {in_path, out_path} = prepare_paths("100-240p")

      assert {:ok, pid} = make_pipeline(in_path, out_path)
      assert Pipeline.play(pid) == :ok
      assert_end_of_stream(pid, :sink, :input, 2000)
    end

    test "transcode 20 360p frames with 422 subsampling" do
      {in_path, out_path} = prepare_paths("20-360p-I422")

      assert {:ok, pid} = make_pipeline(in_path, out_path)
      assert Pipeline.play(pid) == :ok
      assert_end_of_stream(pid, :sink, :input, 2000)
    end
  end
end
