defmodule EncoderTest do
  use ExUnit.Case, async: true
  use Membrane.Pipeline

  import Membrane.Testing.Assertions

  alias Membrane.H264
  alias Membrane.RawVideo
  alias Membrane.Testing.Pipeline

  defp prepare_paths(filename, tmp_dir) do
    in_path = "../fixtures/reference-#{filename}.raw" |> Path.expand(__DIR__)
    out_path = Path.join(tmp_dir, "output-encode-#{filename}.h264")
    {in_path, out_path}
  end

  defp make_pipeline(in_path, out_path, width, height, format) do
    Pipeline.start_link_supervised!(
      spec:
        child(:file_src, %Membrane.File.Source{chunk_size: 40_960, location: in_path})
        |> child(:praser, %RawVideo.Parser{width: width, height: height, pixel_format: format})
        |> child(:encoder, %H264.FFmpeg.Encoder{preset: :fast, crf: 30})
        |> child(:sink, %Membrane.File.Sink{location: out_path})
    )
  end

  defp perform_test(filename, tmp_dir, width, height, format \\ :I420) do
    {in_path, out_path} = prepare_paths(filename, tmp_dir)

    pid = make_pipeline(in_path, out_path, width, height, format)
    assert_end_of_stream(pid, :sink, :input, 4000)
    Pipeline.terminate(pid)
  end

  describe "EncodingPipeline should" do
    @describetag :tmp_dir
    test "encode 10 720p frames", ctx do
      perform_test("10-720p", ctx.tmp_dir, 1280, 720)
    end

    test "encode 100 240p frames", ctx do
      perform_test("100-240p", ctx.tmp_dir, 340, 240)
    end

    test "encode 20 360p frames with 422 subsampling", ctx do
      perform_test("20-360p-I422", ctx.tmp_dir, 480, 360, :I422)
    end
  end
end
