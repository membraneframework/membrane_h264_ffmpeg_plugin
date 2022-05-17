defmodule Membrane.H264.FFmpeg.Parser.IntegrationTest do
  use ExUnit.Case
  use Bunch
  import Membrane.ParentSpec
  import Membrane.Testing.Assertions

  alias Membrane.Testing

  @fixtures_dir "./test/fixtures/"
  @no_params_stream File.read!("test/fixtures/input-10-no-pps-sps.h264")
  @stream_with_params File.read!("test/fixtures/input-10-720p.h264")
  @input_caps %Membrane.H264.RemoteStream{
    decoder_configuration_record:
      <<1, 2, 131, 242, 255, 225, 0, 8, 103, 66, 0, 13, 233, 2, 131, 242, 1, 0, 5, 104, 206, 1,
        15, 32>>,
    stream_format: :byte_stream
  }

  @tag :tmp_dir
  test "Test with skip_until_parameter? and RemoteStream", %{tmp_dir: tmp_dir} do
    tmp_dir = "./tmp"
    input_chunks = Bunch.Binary.chunk_every(@no_params_stream, 1024)
    # input_chunks = Bunch.Binary.chunk_every(@stream_with_params, 1024)
    output_file = Path.join(tmp_dir, "output.h264")
    # reference_file = Path.join(@fixtures_dir, "reference.h264")
    reference_file = Path.join(@fixtures_dir, "reference-10-720p.raw")

    {:ok, pipeline} =
      create_pipeline(input_chunks, output_file)
      |> Testing.Pipeline.start_link()

    play_and_validate(pipeline, reference_file, output_file)
  end

  defp create_pipeline(input_chunks, output_file) do
    [
      children: [
        source: %Testing.Source{
          output: input_chunks,
          caps: @input_caps
        },
        parser: %Membrane.H264.FFmpeg.Parser{
          skip_until_parameters?: false
        },
        sink: %Membrane.File.Sink{
          location: output_file
        }
      ],
      links: [
        link(:source)
        |> to(:parser)
        |> to(:sink)
      ]
    ]
  end

  defp play_and_validate(pipeline, reference_file, output_file) do
    Testing.Pipeline.play(pipeline)
    assert_pipeline_playback_changed(pipeline, :prepared, :playing)
    assert_start_of_stream(pipeline, :sink)
    assert_end_of_stream(pipeline, :sink)
    Testing.Pipeline.terminate(pipeline, blocking?: true)
    assert_pipeline_playback_changed(pipeline, :prepared, :stopped)

    reference_file = File.read!(reference_file)
    result_file = File.read!(output_file)

    assert byte_size(reference_file) == byte_size(result_file)
    assert reference_file == result_file
  end
end
