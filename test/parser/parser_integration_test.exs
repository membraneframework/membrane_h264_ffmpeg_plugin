defmodule Membrane.H264.FFmpeg.Parser.IntegrationTest do
  use ExUnit.Case
  use Bunch
  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.Testing

  @fixtures_dir "./test/fixtures/"
  @tmp_dir "./tmp/ParserTest/"
  @no_params_stream File.read!("test/fixtures/input-10-no-pps-sps.h264")
  @stream_with_params_change File.read!("test/fixtures/input-sps-pps-non-idr-sps-pps-idr.h264")
  @input_stream_format %Membrane.H264.RemoteStream{
    decoder_configuration_record:
      <<1, 2, 131, 242, 255, 225, 0, 28, 103, 100, 0, 31, 172, 217, 64, 80, 5, 187, 1, 106, 2, 2,
        2, 128, 0, 0, 3, 0, 128, 0, 0, 30, 71, 140, 24, 203, 1, 0, 5, 104, 235, 236, 178, 44>>,
    alignment: :au
  }

  setup_all do
    File.mkdir_p!(Path.dirname(@tmp_dir))
  end

  test "if it won't crash when parameters change before I-frame" do
    input_chunks =
      Bunch.Binary.chunk_every_rem(@stream_with_params_change, 1024)
      |> then(fn {a, b} -> a ++ [b] end)

    parser = %Membrane.H264.FFmpeg.Parser{
      skip_until_parameters?: false,
      skip_until_keyframe?: true,
      alignment: :nalu
    }

    pipeline =
      Testing.Pipeline.start_link_supervised!(
        structure:
          child(:source, %Testing.Source{output: input_chunks})
          |> child(:parser, parser)
          |> child(:sink, Testing.Sink)
      )

    assert_sink_stream_format(pipeline, :sink, _stream_format)
    assert_sink_buffer(pipeline, :sink, _buffer)
    assert_end_of_stream(pipeline, :sink)
  end

  test "if it will turn off the skip_until_parameters? option if the RemoteStream stream_format is provided" do
    input_chunks = Bunch.Binary.chunk_every(@no_params_stream, 1024)
    output_file = Path.join(@tmp_dir, "output2.h264")
    reference_file = Path.join(@fixtures_dir, "reference-10-720p-no-pps-sps.h264")

    pipeline =
      create_pipeline(input_chunks, output_file, true)
      |> Testing.Pipeline.start_link_supervised!()

    play_and_validate(pipeline, reference_file, output_file)
  end

  defp create_pipeline(input_chunks, output_file, skip_until_parameters?) do
    [
      structure:
        child(:source, %Testing.Source{
          output: input_chunks,
          stream_format: @input_stream_format
        })
        |> child(:parser, %Membrane.H264.FFmpeg.Parser{
          skip_until_parameters?: skip_until_parameters?
        })
        |> child(:sink, %Membrane.File.Sink{
          location: output_file
        })
    ]
  end

  defp play_and_validate(pipeline, reference_file, output_file) do
    assert_pipeline_play(pipeline)
    assert_start_of_stream(pipeline, :sink)
    assert_end_of_stream(pipeline, :sink)

    reference_file = File.read!(reference_file)
    result_file = File.read!(output_file)

    assert byte_size(reference_file) == byte_size(result_file)
    assert reference_file == result_file
  end
end
