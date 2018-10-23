defmodule DecodingTest do
  alias Membrane.Pipeline
  use ExUnit.Case

  def prepare_paths(filename) do
    in_path = "fixtures/reference-#{filename}.raw" |> Path.expand(__DIR__)
    out_path = "/tmp/output-encode-#{filename}.h264"
    File.rm(out_path)
    on_exit(fn -> File.rm(out_path) end)
    {in_path, out_path}
  end

  def make_pipeline(in_path, out_path, width, height) do
    Pipeline.start_link(
      EncodingPipeline,
      %{in: in_path, out: out_path, pid: self(), format: :I420, width: width, height: height},
      []
    )
  end

  describe "EncodingPipeline should" do
    test "encode 10 720p frames" do
      {in_path, out_path} = prepare_paths("10-720p")

      assert {:ok, pid} = make_pipeline(in_path, out_path, 1280, 720)
      assert Pipeline.play(pid) == :ok
      assert_receive :eos, 1000
    end

    test "encode 100 240p frames" do
      {in_path, out_path} = prepare_paths("100-240p")

      assert {:ok, pid} = make_pipeline(in_path, out_path, 320, 240)
      assert Pipeline.play(pid) == :ok
      assert_receive :eos, 1000
    end
  end
end
