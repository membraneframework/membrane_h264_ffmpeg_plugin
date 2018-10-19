defmodule TranscodingTest do
  alias Membrane.Pipeline
  use ExUnit.Case

  def prepare_paths(filename) do
    in_path = "fixtures/input-#{filename}.h264" |> Path.expand(__DIR__)
    out_path = "/tmp/output-transcode-#{filename}.h264"
    File.rm(out_path)
    on_exit(fn -> File.rm(out_path) end)
    {in_path, out_path}
  end

  def make_pipeline(in_path, out_path) do
    Pipeline.start_link(TranscodingPipeline, %{in: in_path, out: out_path, pid: self()}, [])
  end

  describe "TranscodingPipeline should" do
    test "transcode 10 720p frames" do
      {in_path, out_path} = prepare_paths("10-720p")

      assert {:ok, pid} = make_pipeline(in_path, out_path)
      assert Pipeline.play(pid) == :ok
      assert_receive :eos, 1000
    end

    test "transcode 100 240p frames" do
      {in_path, out_path} = prepare_paths("100-240p")

      assert {:ok, pid} = make_pipeline(in_path, out_path)
      assert Pipeline.play(pid) == :ok
      assert_receive :eos, 1000
    end
  end
end
