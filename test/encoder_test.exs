defmodule EncoderTest do
  alias Membrane.Pipeline
  use ExUnit.Case

  def prepare_paths(filename) do
    in_path = "fixtures/input-#{filename}.h264" |> Path.expand(__DIR__)
    out_path = "/tmp/output-#{filename}.h264"
    File.rm(out_path)
    {in_path, out_path}
  end

  describe "[Integration]" do
    test "Transcode 10 720p frames" do
      {in_path, out_path} = prepare_paths("10-720p")

      {:ok, pid} =
        Pipeline.start_link(TranscodingPipeline, %{in: in_path, out: out_path, pid: self()}, [])

      assert Pipeline.play(pid) == :ok
      assert_receive :eos, 1000
    end
  end

  test "encode 100 240p frames" do
    alias Membrane.Element.FFmpeg.H264.Encoder.Native, as: Enc

    in_path = "fixtures/reference-100-240p.raw" |> Path.expand(__DIR__)

    assert {:ok, file} = File.read(in_path)
    assert {:ok, ref} = Enc.create(320, 240, :I420, :fast, :high, 30, 1, 23)
    assert <<frame::bytes-size(115_200), tail::binary>> = file
    assert {:ok, frames} = Enc.encode(frame, ref)
  end
end
