defmodule Membrane.H264.FFmpeg.Parser do
  @moduledoc """
  Membrane element providing parser for H264 encoded video stream.
  Uses the parser provided by FFmpeg.

  By default, this parser splits the stream into h264 access units,
  each of which is a sequence of NAL units corresponding to one
  video frame, and equips them with the following metadata entries
  under `:h264` key:
  - `key_frame?: boolean` - determines whether the frame is a h264
    I frame.

  Setting custom packetization options affects metadata, see `alignment`
  and `attach_nalus?` options for details.

  This Parser is also capable of handling out-of-band parameters in the form of Decoder Configuration Record.
  To inject it, simply send `t:Membrane.H264.RemoteStream.t/0` caps containing the Decoder Configuration Record to this element.
  There are however some limitations:
  - `t:Membrane.H264.RemoteStream.t/0` caps need to be send only before the first buffer.
    Sending them during the stream will cause an error
  - SPS and PPS will be extracted from Decoder Configuration Record and added to the payload of the very first buffer without any checks of in-band parameters.
    This might result in duplicated SPS and PPS. It shouldn't be a problem, unless you send an incorrect Decoder Configuration Record that doesn't match the stream.
  """
  use Membrane.Filter
  use Bunch

  require Membrane.Logger

  alias __MODULE__.{NALu, Native}
  alias Membrane.Buffer
  alias Membrane.H264

  def_input_pad :input,
    demand_unit: :buffers,
    demand_mode: :auto,
    caps: :any

  def_output_pad :output,
    demand_mode: :auto,
    caps: {H264, stream_format: :byte_stream}

  def_options framerate: [
                type: :framerate,
                spec: H264.framerate_t() | nil,
                default: nil,
                description: """
                Framerate of video stream, see `t:Membrane.H264.framerate_t/0`
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
                Stream units carried by each output buffer. See `t:Membrane.H264.alignment_t/0`.

                If alignment is `:nal`, the following metadata entries are added:
                - `type` - h264 nalu type
                - `new_access_unit: access_unit_metadata` - added whenever the new access unit starts.
                  `access_unit_metadata` is the metadata that would be merged into the buffer metadata
                   normally (if `alignment` was `:au`).
                - `end_access_unit: true` - added for each NALu that ends an access unit.
                """
              ],
              attach_nalus?: [
                type: :boolean,
                default: false,
                description: """
                Determines whether to attach NAL units list to the metadata when `alignment` option
                is set to `:au`. For details see `t:Membrane.H264.nalu_in_metadata_t/0`.
                """
              ],
              skip_until_keyframe?: [
                type: :boolean,
                default: false,
                description: """
                Determines whether to drop the stream until the first key frame is received.
                """
              ],
              skip_until_parameters?: [
                type: :boolean,
                default: true,
                description: """
                Determines whether to drop the stream until the first set of SPS and PPS is received.
                """
              ],
              max_b_frames: [
                type: :integer,
                default: 5,
                description: """
                Defines the maximum expected number of consequent b-frames in the stream.
                """
              ]

  @impl true
  def handle_init(opts) do
    state =
      Map.from_struct(opts)
      |> Map.merge(%{
        pending_caps: nil,
        parser_ref: nil,
        partial_frame: <<>>,
        frame_prefix: opts.sps <> opts.pps,
        metadata: nil,
        acc: <<>>,
        profile_has_b_frames?: nil
      })

    {:ok, state}
  end

  @impl true
  def handle_stopped_to_prepared(_ctx, state) do
    case Native.create() do
      {:ok, parser_ref} ->
        {:ok, %{state | parser_ref: parser_ref}}

      {:error, reason} ->
        {{:error, reason}, state}
    end
  end

  @impl true
  def handle_prepared_to_playing(_ctx, %{skip_until_keyframe: true} = state) do
    {{:ok, event: {:input, %Membrane.KeyframeRequestEvent{}}}, state}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_process(
        :input,
        buffer,
        _ctx,
        %{skip_until_parameters?: true, frame_prefix: <<>>} = state
      ) do
    data = state.acc <> buffer.payload

    {parsed, _au_info, unparsed} = NALu.parse(data)

    case find_parameters(parsed) do
      {:error, :not_enough_buffers} ->
        {:ok, %{state | acc: data}}

      {:ok, buffers} ->
        contents =
          Enum.map_join(buffers, fn %{prefixed_poslen: {pos, len}} ->
            <<_prefix::binary-size(pos), nalu::binary-size(len), _rest::binary>> = data
            nalu
          end)

        do_process(%{buffer | payload: contents <> unparsed}, %{
          state
          | skip_until_parameters?: false
        })
    end
  end

  # If frame prefix has been applied, proceed to parsing the buffer
  @impl true
  def handle_process(:input, buffer, _ctx, %{frame_prefix: <<>>} = state) do
    do_process(buffer, state)
  end

  # If there is a frame prefix to be applied, check that there are no in-band parameters and write the prefix if necessary
  @impl true
  def handle_process(:input, %Buffer{} = buffer, _ctx, state) when state.frame_prefix != <<>> do
    buffer = Map.update!(buffer, :payload, &(state.frame_prefix <> &1))
    do_process(buffer, %{state | frame_prefix: <<>>})
  end

  defp do_process(%Buffer{payload: payload} = buffer, state) do
    case Native.parse(payload, state.parser_ref) do
      {:ok, sizes, decoding_order_numbers, presentation_order_numbers, resolution_changes} ->
        metadata = %{buffer_metadata: buffer.metadata, pts: buffer.pts, dts: buffer.dts}

        {bufs, state} =
          parse_access_units(
            payload,
            Enum.with_index(sizes),
            metadata,
            decoding_order_numbers,
            presentation_order_numbers,
            state
          )

        {actions, state} = parse_resolution_changes(state, bufs, resolution_changes)
        {{:ok, actions}, state}

      {:error, reason} ->
        {{:error, reason}, state}
    end
  end

  # analyze resolution changes and generate appropriate caps before corresponding buffers
  defp parse_resolution_changes(state, bufs, resolution_changes, acc \\ [])

  defp parse_resolution_changes(state, [], [], []) do
    {[], state}
  end

  defp parse_resolution_changes(state, bufs, [], acc) do
    bufs = Enum.map(bufs, fn {_au, buf} -> buf end)

    caps =
      if state.pending_caps != nil do
        [caps: {:output, state.pending_caps}]
      else
        []
      end

    actions = Enum.reverse([buffer: {:output, bufs}] ++ caps ++ acc)

    {actions, %{state | pending_caps: nil}}
  end

  defp parse_resolution_changes(state, bufs, [meta | resolution_changes], acc) do
    {old_bufs, next_bufs} = Enum.split_while(bufs, fn {au, _buf} -> au < meta.index end)
    {next_caps, state} = mk_caps(state, meta.width, meta.height)

    {caps, state} =
      if old_bufs == [],
        do: {[], %{state | pending_caps: next_caps}},
        else: {[caps: {:output, next_caps}], state}

    buffers_before_change =
      case old_bufs do
        [] ->
          []

        _non_empty ->
          old_bufs = Enum.map(old_bufs, fn {_au, buf} -> buf end)
          [buffer: {:output, old_bufs}]
      end

    {pending_caps, state} =
      if state.pending_caps != nil and buffers_before_change != [] do
        {[caps: {:output, state.pending_caps}], %{state | pending_caps: nil}}
      else
        {[], state}
      end

    parse_resolution_changes(
      state,
      next_bufs,
      resolution_changes,
      caps ++ buffers_before_change ++ pending_caps ++ acc
    )
  end

  @impl true
  def handle_caps(:input, %Membrane.H264.RemoteStream{}, ctx, _state)
      when ctx.pads.input.start_of_stream?,
      do: raise("Cannot send Membrane.H264.RemoteStream caps after the stream has started")

  @impl true
  def handle_caps(:input, %Membrane.H264.RemoteStream{} = caps, _ctx, state) do
    {:ok, %{sps: sps, pps: pps}} =
      Membrane.H264.FFmpeg.Parser.DecoderConfiguration.parse(caps.decoder_configuration_record)

    frame_prefix =
      Enum.concat([[state.frame_prefix || <<>>], sps, pps])
      |> Enum.join(<<0, 0, 1>>)

    if state.skip_until_parameters? do
      Membrane.Logger.warn("""
      Flag skip_until_parameters? is not compatible with Membrane.H264.RemoteStream caps.
      It is being automatically disabled.
      """)
    end

    {:ok, %{state | frame_prefix: frame_prefix, skip_until_parameters?: false}}
  end

  @impl true
  def handle_caps(:input, _caps, _ctx, state) do
    # ignoring caps, new ones will be generated in handle_process
    {:ok, state}
  end

  @impl true
  def handle_end_of_stream(:input, ctx, state) do
    with {:ok, sizes, decoding_order_numbers, presentation_order_numbers, resolution} <-
           Native.flush(state.parser_ref) do
      {bufs, state} =
        parse_access_units(
          <<>>,
          Enum.with_index(sizes),
          state.metadata,
          decoding_order_numbers,
          presentation_order_numbers,
          state
        )

      if state.partial_frame != <<>> do
        Membrane.Logger.warn("Discarding incomplete frame because of end of stream")
      end

      {caps, state} = mk_caps(state, resolution.width, resolution.height)
      caps_actions = if caps != ctx.pads.output.caps, do: [caps: {:output, caps}], else: []

      bufs = Enum.map(bufs, fn {_au, buf} -> buf end)
      actions = caps_actions ++ [buffer: {:output, bufs}, end_of_stream: :output]
      {{:ok, actions}, state}
    end
  end

  @impl true
  def handle_prepared_to_stopped(_ctx, state) do
    {:ok, %{state | parser_ref: nil}}
  end

  defp parse_access_units(
         input,
         au_sizes,
         metadata,
         decoding_order_numbers,
         presentation_order_numbers,
         %{partial_frame: <<>>} = state
       ) do
    state = %{state | metadata: metadata}

    {buffers, input, state} =
      do_parse_access_units(
        input,
        au_sizes,
        metadata,
        decoding_order_numbers,
        presentation_order_numbers,
        state,
        []
      )

    {buffers, %{state | partial_frame: input}}
  end

  defp parse_access_units(
         input,
         [],
         _metadata,
         _decoding_order_numbers,
         _presentation_order_numbers,
         state
       ) do
    {[], %{state | partial_frame: state.partial_frame <> input}}
  end

  defp parse_access_units(
         input,
         [au_size | au_sizes],
         metadata,
         [decoding_order_number | decoding_order_numbers],
         [presentation_order_number | presentation_order_numbers],
         state
       ) do
    {first_au_buffers, input, state} =
      do_parse_access_units(
        state.partial_frame <> input,
        [au_size],
        state.metadata,
        [decoding_order_number],
        [presentation_order_number],
        state,
        []
      )

    state = %{state | metadata: metadata}

    {buffers, input, state} =
      do_parse_access_units(
        input,
        au_sizes,
        state.metadata,
        decoding_order_numbers,
        presentation_order_numbers,
        state,
        []
      )

    {first_au_buffers ++ buffers, %{state | partial_frame: input}}
  end

  defp do_parse_access_units(
         input,
         [],
         _metadata,
         _decoding_order_numbers,
         _presentation_order_numbers,
         state,
         acc
       ) do
    {acc |> Enum.reverse() |> List.flatten(), input, state}
  end

  defp do_parse_access_units(
         input,
         [{au_size, au_number} | au_sizes],
         metadata,
         [decoding_order_number | decoding_order_numbers],
         [presentation_order_number | presentation_order_numbers],
         state,
         acc
       ) do
    <<au::binary-size(au_size), rest::binary>> = input

    {pts, dts} =
      withl framerate: {frames, seconds} <- state.framerate,
            positive_order_number: true <- presentation_order_number >= 0 do
        pts =
          div(
            presentation_order_number * seconds * Membrane.Time.second(),
            frames
          )

        dts =
          div(
            (decoding_order_number - state.max_b_frames) * seconds * Membrane.Time.second(),
            frames
          )

        {pts, dts}
      else
        positive_order_number: false -> {nil, nil}
        framerate: nil -> {metadata.pts, metadata.dts}
      end

    {nalus, au_metadata, _unparsed} = NALu.parse(au, complete_nalu?: true)
    au_metadata = Map.merge(metadata.buffer_metadata, au_metadata)
    state = Map.update!(state, :skip_until_keyframe?, &(&1 and not au_metadata.h264.key_frame?))

    buffers =
      case state do
        %{skip_until_keyframe?: true} ->
          []

        %{alignment: :au, attach_nalus?: true} ->
          [
            {au_number,
             %Buffer{
               pts: pts,
               dts: dts,
               payload: au,
               metadata: put_in(au_metadata, [:h264, :nalus], nalus)
             }}
          ]

        %{alignment: :au, attach_nalus?: false} ->
          [{au_number, %Buffer{pts: pts, dts: dts, payload: au, metadata: au_metadata}}]

        %{alignment: :nal} ->
          Enum.map(nalus, fn nalu ->
            {au_number,
             %Buffer{
               pts: pts,
               dts: dts,
               payload: :binary.part(au, nalu.prefixed_poslen),
               metadata: Map.merge(metadata.buffer_metadata, nalu.metadata)
             }}
          end)
      end

    do_parse_access_units(
      rest,
      au_sizes,
      metadata,
      decoding_order_numbers,
      presentation_order_numbers,
      state,
      [buffers | acc]
    )
  end

  defp mk_caps(state, width, height) do
    {:ok, profile} = Native.get_profile(state.parser_ref)

    {
      %H264{
        width: width,
        height: height,
        framerate: state.framerate || {0, 1},
        alignment: state.alignment,
        nalu_in_metadata?: state.attach_nalus?,
        stream_format: :byte_stream,
        profile: profile
      },
      %{state | profile_has_b_frames?: profile_has_b_frames?(profile)}
    }
  end

  defp profile_has_b_frames?(profile) do
    if profile in ["constrained_baseline", "baseline"], do: false, else: true
  end

  defp find_parameters(data, looking_for \\ [:sps, :pps])

  defp find_parameters(data, []) do
    {:ok, data}
  end

  defp find_parameters([], _looking_for), do: {:error, :not_enough_buffers}

  defp find_parameters(data, looking_for) do
    {before_buffers, after_buffers} =
      Enum.split_while(data, &(not Enum.member?(looking_for, &1.metadata.h264.type)))

    before_buffers =
      Enum.reject(before_buffers, &Enum.member?([:idr, :non_idr], &1.metadata.h264.type))

    with [%{metadata: %{h264: %{type: type}}} | _rest] <- after_buffers,
         {:ok, after_buffers} <- find_parameters(after_buffers, looking_for -- [type]) do
      {:ok, before_buffers ++ after_buffers}
    else
      [] -> {:error, :not_enough_buffers}
      error -> error
    end
  end
end
