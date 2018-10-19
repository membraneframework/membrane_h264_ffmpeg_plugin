defmodule DecoderTest do
  alias Membrane.Pipeline
  use ExUnit.Case

  def prepare_paths(filename) do
    in_path = "fixtures/input-#{filename}.h264" |> Path.expand(__DIR__)
    reference_path = "fixtures/reference-#{filename}.raw" |> Path.expand(__DIR__)
    out_path = "/tmp/output-decoding-#{filename}.raw"
    File.rm(out_path)
    on_exit(fn -> File.rm(out_path) end)
    {in_path, reference_path, out_path}
  end

  def make_pipeline(in_path, out_path) do
    Pipeline.start_link(DecodingPipeline, %{in: in_path, out: out_path, pid: self()}, [])
  end

  def assert_files_equal(file_a, file_b) do
    assert {:ok, a} = File.read(file_a)
    assert {:ok, b} = File.read(file_b)
    assert a == b
  end

  describe "DecodingPipeline should" do
    test "decode 10 720p frames" do
      {in_path, ref_path, out_path} = prepare_paths("10-720p")

      assert {:ok, pid} = make_pipeline(in_path, out_path)

      assert Pipeline.play(pid) == :ok
      assert_receive :eos, 500
      assert_files_equal(out_path, ref_path)
    end

    test "decode 100 240p frames" do
      {in_path, ref_path, out_path} = prepare_paths("100-240p")

      assert {:ok, pid} = make_pipeline(in_path, out_path)

      assert Pipeline.play(pid) == :ok
      assert_receive :eos, 1000
      assert_files_equal(out_path, ref_path)
    end
  end
end
