defmodule Membrane.Element.FFmpeg.H264.Parser do
  @moduledoc """
  Membrane element providing parser for H264 encoded video stream.
  Uses the parser provided by FFmpeg.

  It receives buffers with binary payloads and splits them into frames.
  """
  use Membrane.Filter
  alias __MODULE__.Native
  alias Membrane.Buffer
  alias Membrane.Caps.Video.H264
  use Membrane.Log

  def_input_pad :input,
    demand_unit: :buffers,
    caps: :any

  def_output_pad :output,
    caps: {H264, stream_format: :byte_stream, alignment: :au}

  def_options framerate: [
                type: :framerate,
                spec: H264.framerate_t(),
                default: {0, 1},
                description: """
                Framerate of video stream, see `t:Membrane.Caps.Video.H264.framerate_t/0`
                """
              ],
              sps: [
                type: :binary,
                default: <<>>
              ],
              pps: [
                type: :binary,
                default: <<>>
              ]

  @impl true
  def handle_init(opts) do
    first_frame_prefix = (opts.sps || <<>>) <> (opts.pps || <<>>)

    state = %{
      parser_ref: nil,
      partial_frame: "",
      first_frame_prefix: first_frame_prefix
    }

    {:ok, opts |> Map.merge(state)}
  end

  @impl true
  def handle_stopped_to_prepared(_ctx, state) do
    with {:ok, parser_ref} <- Native.create() do
      {:ok, %{state | parser_ref: parser_ref}}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  @impl true
  def handle_demand(:output, _size, :buffers, _ctx, state) do
    {{:ok, demand: :input}, state}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: payload}, ctx, state) do
    %{parser_ref: parser_ref, partial_frame: partial_frame} = state
    payload = state.first_frame_prefix <> payload

    with {:ok, sizes} <- Native.parse(payload, parser_ref),
         {bufs, rest} <- gen_bufs_by_sizes(partial_frame <> payload, sizes) do
      state = %{state | partial_frame: rest}
      actions = [buffer: {:output, bufs}, redemand: :output]

      actions =
        if ctx.pads.output.caps == nil and bufs != [] do
          {:ok, width, height, profile} = Native.get_parsed_meta(parser_ref)

          caps = %H264{
            width: width,
            height: height,
            framerate: state.framerate,
            alignment: :au,
            stream_format: :byte_stream,
            profile: profile
          }

          [{:caps, {:output, caps}} | actions]
        else
          actions
        end

      {{:ok, actions}, %{state | first_frame_prefix: <<>>}}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    %{parser_ref: parser_ref, partial_frame: partial_frame} = state

    with {:ok, sizes} <- Native.flush(parser_ref) do
      {bufs, rest} = gen_bufs_by_sizes(partial_frame, sizes)

      if rest != "" do
        warn("Discarding incomplete frame because of end of stream")
      end

      state = %{state | partial_frame: ""}

      actions = [
        buffer: {:output, bufs},
        end_of_stream: :output,
        notify: {:end_of_stream, :input}
      ]

      {{:ok, actions}, state}
    end
  end

  @impl true
  def handle_prepared_to_stopped(_ctx, state) do
    {:ok, %{state | parser_ref: nil}}
  end

  defp gen_bufs_by_sizes(input, sizes) do
    Enum.map_reduce(sizes, input, fn size, stream ->
      <<frame::bytes-size(size), rest::binary>> = stream
      {%Buffer{payload: frame}, rest}
    end)
  end
end
