defmodule Membrane.H264.FFmpeg.Parser.Test do
  use ExUnit.Case, async: true

  alias Membrane.Buffer
  alias Membrane.H264.FFmpeg.Parser

  @no_params_stream File.read!("test/fixtures/input-10-no-pps-sps.h264")
  @stream_with_params File.read!("test/fixtures/input-10-720p.h264")

  @input_caps %Membrane.H264.RemoteStream{
    decoder_configuration_record:
      <<1, 2, 131, 242, 255, 225, 0, 28, 103, 100, 0, 31, 172, 217, 64, 80, 5, 187, 1, 106, 2, 2,
        2, 128, 0, 0, 3, 0, 128, 0, 0, 30, 71, 140, 24, 203, 1, 0, 5, 104, 235, 236, 178, 44>>,
    stream_format: :byte_stream
  }
  @expected_prefix <<0, 0, 1, 103, 100, 0, 31, 172, 217, 64, 80, 5, 187, 1, 106, 2, 2, 2, 128, 0,
                     0, 3, 0, 128, 0, 0, 30, 71, 140, 24, 203, 0, 0, 1, 104, 235, 236, 178, 44>>

  describe "Check if H264.RemoteStream caps" do
    test "are parsed correctly" do
      state = init_pipeline()
      assert state.frame_prefix == @expected_prefix
    end

    test "allow the Parser to insert missing pps and sps" do
      state = init_pipeline()

      assert {{:ok, actions}, %{frame_prefix: <<>>}} =
               Parser.handle_process(:input, %Buffer{payload: @no_params_stream}, nil, state)

      nalu = get_nalu_types(actions) |> Enum.take(2)
      assert Enum.all?([:sps, :pps], &Enum.member?(nalu, &1))
    end

    test "have lower priority than in-band parameters" do
      state = init_pipeline()

      assert {{:ok, actions}, %{frame_prefix: <<>>}} =
               Parser.handle_process(:input, %Buffer{payload: @stream_with_params}, nil, state)

      nalu = get_nalu_types(actions) |> Enum.take(3)
      assert Enum.uniq(nalu) == nalu
    end
  end

  test "Check if Parser won't crash if short first buffer is sent" do
    state = init_pipeline()
    <<payload1::binary-size(5), payload2::binary>> = @no_params_stream

    assert {{:ok, []}, new_state} =
             Parser.handle_process(:input, %Buffer{payload: payload1}, nil, state)

    assert {{:ok, actions}, %{frame_prefix: <<>>}} =
             Parser.handle_process(:input, %Buffer{payload: payload2}, nil, new_state)

    assert [caps: {:output, _format}, buffer: {:output, buffers}] = actions
    assert length(buffers) > 0

    for buffer <- buffers do
      assert %Buffer{} = buffer
    end
  end

  defp init_pipeline() do
    assert {:ok, state} =
             Parser.handle_init(%Parser{
               framerate: {30, 1},
               skip_until_keyframe?: false
             })

    assert {:ok, state} = Parser.handle_stopped_to_prepared(nil, state)

    assert {:ok, state} = Parser.handle_caps(:input, @input_caps, nil, state)
    state
  end

  defp get_nalu_types(actions) do
    actions
    |> Enum.filter(fn {action, _args} -> action == :buffer end)
    |> Enum.flat_map(fn {:buffer, {:output, payload}} -> Bunch.listify(payload) end)
    |> List.flatten()
    |> hd()
    |> then(& &1.payload)
    |> Parser.NALu.parse()
    |> elem(0)
    |> Enum.map(&get_in(&1, [:metadata, :h264, :type]))
  end
end
