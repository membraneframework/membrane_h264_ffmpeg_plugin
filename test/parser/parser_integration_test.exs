defmodule Membrane.H264.FFmpeg.Parser.IntegrationTest do
  use ExUnit.Case
  use Bunch
  import Membrane.ParentSpec
  import Membrane.Testing.Assertions

  alias Membrane.Testing

  @fixtures_dir "./test/fixtures/"
  @tmp_dir "./tmp/"
  @no_params_stream File.read!("test/fixtures/input-10-no-pps-sps.h264")
  @stream_with_params File.read!("test/fixtures/input-10-720p.h264")
  @input_caps %Membrane.H264.RemoteStream{
    decoder_configuration_record:
      <<1, 2, 131, 242, 255, 225, 0, 28, 103, 100, 0, 31, 172, 217, 64, 80, 5, 187, 1, 106, 2, 2,
        2, 128, 0, 0, 3, 0, 128, 0, 0, 30, 71, 140, 24, 203, 1, 0, 5, 104, 235, 236, 178, 44>>,
    stream_format: :byte_stream
  }

  test "if it won't add parameters at the beggining if they are present in the input file" do
    {input_chunks, rem_chunk} = Bunch.Binary.chunk_every_rem(@stream_with_params, 1024)
    output_file = Path.join(@tmp_dir, "output1.h264")
    reference_file = Path.join(@fixtures_dir, "input-10-720p.h264")

    {:ok, pipeline} =
      create_pipeline(input_chunks ++ [rem_chunk], output_file, false)
      |> Testing.Pipeline.start_link()

    play_and_validate(pipeline, reference_file, output_file)
  end

  test "if it will turn off the skip_unit_parameters? option if the RemoteStream caps are provided" do
    input_chunks = Bunch.Binary.chunk_every(@no_params_stream, 1024)
    output_file = Path.join(@tmp_dir, "output2.h264")
    reference_file = Path.join(@fixtures_dir, "reference-10-720p-no-pps-sps.h264")

    {:ok, pipeline} =
      create_pipeline(input_chunks, output_file, true)
      |> Testing.Pipeline.start_link()

    play_and_validate(pipeline, reference_file, output_file)
  end

  defp create_pipeline(input_chunks, output_file, skip_until_parameters?) do
    [
      children: [
        source: %Testing.Source{
          output: input_chunks,
          caps: @input_caps
        },
        parser: %Membrane.H264.FFmpeg.Parser{
          skip_until_parameters?: skip_until_parameters?
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
