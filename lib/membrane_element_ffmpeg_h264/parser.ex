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
              sps: [
                type: :binary,
                default: <<>>,
                description: """
                Sequence Parameter Set NAL unit - if absent in the stream, should
                be provided via this option.
                """
              ],
              pps: [
                type: :binary,
                default: <<>>,
                description: """
                Picture Parameter Set NAL unit - if absent in the stream, should
                be provided via this option.
                """
              ],
              alignment: [
                type: :atom,
                spec: :au | :nal,
                default: :au,
                description: """
                Stream units carried by each output buffer. See `t:Membrane.Caps.Video.H264.alignment_t`
                """
              ],
              attach_nalus?: [
                type: :boolean,
                default: true
              ]

  @impl true
  def handle_init(opts) do
    state = %{
      parser_ref: nil,
      partial_frame: <<>>,
      first_frame_prefix: opts.sps <> opts.pps,
      first_frame?: true,
      framerate: opts.framerate,
      alignment: opts.alignment,
      attach_nalus?: opts.attach_nalus?,
      metadata: nil,
      timestamp: 0
    }

    {:ok, state}
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
  def handle_process(:input, buffer, ctx, %{first_frame?: true} = state) do
    buffer = Map.update!(buffer, :payload, &(state.first_frame_prefix <> &1))
    handle_process(:input, buffer, ctx, %{state | first_frame?: false})
  end

  @impl true
  def handle_process(:input, %Buffer{payload: payload, metadata: metadata}, ctx, state) do
    with {:ok, sizes} <- Native.parse(payload, state.parser_ref) do
      {bufs, state} = parse_access_units(payload, sizes, metadata, state)

      caps =
        if ctx.pads.output.caps == nil and bufs != [] do
          [caps: {:output, mk_caps(state)}]
        else
          []
        end

      {{:ok, caps ++ [buffer: {:output, bufs}, redemand: :output]}, state}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    with {:ok, sizes} <- Native.flush(state.parser_ref) do
      {bufs, state} = parse_access_units(<<>>, sizes, state.metadata, state)

      if state.partial_frame != <<>> do
        warn("Discarding incomplete frame because of end of stream")
      end

      actions = [buffer: {:output, bufs}, end_of_stream: :output]
      {{:ok, actions}, state}
    end
  end

  @impl true
  def handle_prepared_to_stopped(_ctx, state) do
    {:ok, %{state | parser_ref: nil}}
  end

  defp parse_access_units(input, au_sizes, metadata, %{partial_frame: <<>>} = state) do
    state = update_metadata(metadata, state)
    {buffers, input, state} = do_parse_access_units(input, au_sizes, metadata, state, [])
    {buffers, %{state | partial_frame: input}}
  end

  defp parse_access_units(input, [], _metadata, state) do
    {[], %{state | partial_frame: state.partial_frame <> input}}
  end

  defp parse_access_units(input, [au_size | au_sizes], metadata, state) do
    {first_au_buffers, input, state} =
      do_parse_access_units(state.partial_frame <> input, [au_size], state.metadata, state, [])

    state = update_metadata(metadata, state)
    {buffers, input, state} = do_parse_access_units(input, au_sizes, metadata, state, [])
    {first_au_buffers ++ buffers, %{state | partial_frame: input}}
  end

  defp do_parse_access_units(input, [], _metadata, state, acc) do
    {Enum.reverse(acc), input, state}
  end

  defp do_parse_access_units(input, [au_size | au_sizes], metadata, state, acc) do
    <<au::binary-size(au_size), rest::binary>> = input
    metadata = Map.put(metadata, :timestamp, state.timestamp)
    {nalus, au_metadata} = NALu.parse(au)
    au_metadata = Map.merge(metadata, au_metadata)

    buffers =
      case state do
        %{alignment: :au, attach_nalus?: true} ->
          [%Buffer{payload: au, metadata: Map.put(au_metadata, :nalus, nalus)}]

        %{alignment: :au, attach_nalus?: false} ->
          [%Buffer{payload: au, metadata: au_metadata}]

        %{alignment: :nal} ->
          Enum.map(nalus, fn nalu ->
            %Buffer{
              payload: :binary.part(au, nalu.prefixed_poslen),
              metadata: Map.merge(metadata, nalu.metadata)
            }
          end)
      end

    do_parse_access_units(rest, au_sizes, metadata, bump_timestamp(state), [buffers | acc])
  end

  defp update_metadata(%{timestamp: timestamp} = metadata, state) do
    %{state | timestamp: timestamp, metadata: metadata}
  end

  defp update_metadata(metadata, state) do
    %{state | metadata: metadata}
  end

  defp bump_timestamp(%{framerate: {0, _}} = state) do
    state
  end

  defp bump_timestamp(state) do
    use Ratio
    %{timestamp: timestamp, framerate: {num, denom}} = state
    timestamp = timestamp + Ratio.new(denom * Membrane.Time.second(), num)
    %{state | timestamp: timestamp}
  end

  defp mk_caps(state) do
    {:ok, width, height, profile} = Native.get_parsed_meta(state.parser_ref)

    %H264{
      width: width,
      height: height,
      framerate: state.framerate,
      alignment: state.alignment,
      stream_format: :byte_stream,
      profile: profile
    }
  end
end
