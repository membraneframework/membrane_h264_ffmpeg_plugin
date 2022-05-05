defmodule TranscodingTest do
  use ExUnit.Case
  import Membrane.Testing.Assertions
  alias Membrane.H264
  alias Membrane.Testing.Pipeline

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

  defp perform_test(filename, tmp_dir, timeout) do
    in_path = "../fixtures/input-#{filename}.h264" |> Path.expand(__DIR__)
    out_path = Path.join(tmp_dir, "output-transcode-#{filename}.h264")

    assert {:ok, pid} = make_pipeline(in_path, out_path)
    assert_pipeline_playback_changed(pid, :prepared, :playing)
    assert_end_of_stream(pid, :sink, :input, timeout)

    Pipeline.terminate(pid, blocking?: true)
  end

  describe "TranscodingPipeline should" do
    @describetag :tmp_dir
    test "transcode 10 720p frames", ctx do
      perform_test("10-720p", ctx.tmp_dir, 1000)
    end

    test "transcode 100 240p frames", ctx do
      perform_test("100-240p", ctx.tmp_dir, 2000)
    end

    test "transcode 20 360p frames with 422 subsampling", ctx do
      perform_test("20-360p-I422", ctx.tmp_dir, 2000)
    end
  end
end
