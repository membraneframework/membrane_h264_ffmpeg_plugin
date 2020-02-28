defmodule Membrane.Element.FFmpeg.H264.Parser do
  @moduledoc """
  Membrane element providing parser for H264 encoded video stream.
  Uses the parser provided by FFmpeg.

  It receives buffers with binary payloads and splits them into frames.
  """
  use Bunch
  use Membrane.Filter
  use Membrane.Log
  alias __MODULE__.{NALu, Native}
  alias Membrane.Buffer
  alias Membrane.Caps.Video.H264

  def_input_pad :input,
    demand_unit: :buffers,
    caps: :any

  def_output_pad :output,
    caps: {H264, stream_format: :byte_stream}

  def_options framerate: [
                type: :framerate,
                spec: H264.framerate_t(),
                default: {0, 1},
                description: """
                Framerate of video stream, see `t:Membrane.Caps.Video.H264.framerate_t/0`
                """
              ],
              alignment: [
                type: :atom,
                spec: :au | :nal,
                default: :au,
                description: """
                Stream units carried by each output buffer. See `t:Membrane.Caps.Video.H264.alignment_t`
                """
              ]

  @impl true
  def handle_init(opts) do
    {:ok, opts |> Map.merge(%{parser_ref: nil, partial_frame: ""})}
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
  def handle_process(:input, %Buffer{payload: payload, metadata: metadata}, ctx, state) do
    %{parser_ref: parser_ref, partial_frame: partial_frame} = state

    with {:ok, sizes, _flags} <- Native.parse(payload, parser_ref),
         {bufs, rest} <- gen_bufs(partial_frame <> payload, metadata, sizes, state.alignment) do
      state = %{state | partial_frame: rest}
      actions = [buffer: {:output, bufs}, redemand: :output]

      actions =
        if ctx.pads.output.caps == nil and bufs != [] do
          {:ok, width, height, profile} = Native.get_parsed_meta(parser_ref)

          caps = %H264{
            width: width,
            height: height,
            framerate: state.framerate,
            alignment: state.alignment,
            stream_format: :byte_stream,
            profile: profile
          }

          [{:caps, {:output, caps}} | actions]
        else
          actions
        end

      {{:ok, actions}, state}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    %{parser_ref: parser_ref, partial_frame: partial_frame} = state

    with {:ok, sizes, _flags} <- Native.flush(parser_ref) do
      {bufs, rest} = gen_bufs(partial_frame, %{}, sizes, state.alignment)

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

  defp gen_bufs(input, in_metadata, sizes, alignment) do
    Enum.flat_map_reduce(sizes, input, fn size, stream ->
      <<frame::bytes-size(size), rest::binary>> = stream
      {bufs, au_metadata} = NALu.parse(frame)

      case alignment do
        :au ->
          [%Buffer{payload: frame, metadata: Map.merge(in_metadata, au_metadata)}]

        :nal ->
          Enum.map(bufs, fn b ->
            Map.update!(
              b,
              :metadata,
              &(&1 |> Map.merge(%{access_unit: au_metadata}) |> Map.merge(in_metadata))
            )
          end)
      end
      ~> {&1, rest}
    end)
  end
end
