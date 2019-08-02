defmodule DecoderTest do
  use ExUnit.Case
  import Membrane.Testing.Assertions
  alias Membrane.Element
  alias Membrane.Testing.Pipeline

  def prepare_paths(filename) do
    in_path = "../fixtures/input-#{filename}.h264" |> Path.expand(__DIR__)
    reference_path = "../fixtures/reference-#{filename}.raw" |> Path.expand(__DIR__)
    out_path = "/tmp/output-decoding-#{filename}.raw"
    File.rm(out_path)
    on_exit(fn -> File.rm(out_path) end)
    {in_path, reference_path, out_path}
  end

  def make_pipeline(in_path, out_path) do
    Pipeline.start_link(%Pipeline.Options{
      elements: [
        file_src: %Element.File.Source{chunk_size: 40_960, location: in_path},
        parser: Element.FFmpeg.H264.Parser,
        decoder: Element.FFmpeg.H264.Decoder,
        sink: %Element.File.Sink{location: out_path}
      ]
    })
  end

  def assert_files_equal(file_a, file_b) do
    assert {:ok, a} = File.read(file_a)
    assert {:ok, b} = File.read(file_b)
    assert a == b
  end

  def perform_test(filename, timeout) do
    {in_path, ref_path, out_path} = prepare_paths(filename)

    assert {:ok, pid} = make_pipeline(in_path, out_path)
    assert Pipeline.play(pid) == :ok
    assert_end_of_stream(pid, :sink, :input, timeout)
    assert_files_equal(out_path, ref_path)
  end

  describe "DecodingPipeline should" do
    test "decode 10 720p frames" do
      perform_test("10-720p", 500)
    end

    test "decode 100 240p frames" do
      perform_test("100-240p", 1000)
    end

    test "decode 20 360p frames with 422 subsampling" do
      perform_test("20-360p-I422", 1000)
    end
  end
end
