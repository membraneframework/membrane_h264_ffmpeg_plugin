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
  """
  use Membrane.Filter
  use Bunch

  require Membrane.Logger

  alias __MODULE__.{NALu, Native}
  alias Membrane.Buffer
  alias Membrane.H264

  @required_parameter_nalus [:pps, :sps]

  defguardp is_allowed_before_data(nalu) when nalu in [:aud, :sei, :pps, :sps]

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
                Stream units carried by each output buffer. See `t:Membrane.Caps.Video.H264.alignment_t`.

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
                is set to `:au`. For details see `t:Membrane.Caps.Video.H264.nalu_in_metadata_t/0`.
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
              ]

  @impl true
  def handle_init(opts) do
    state = %{
      pending_caps: nil,
      parser_ref: nil,
      partial_frame: <<>>,
      frame_prefix: opts.sps <> opts.pps,
      framerate: opts.framerate,
      alignment: opts.alignment,
      attach_nalus?: opts.attach_nalus?,
      skip_until_keyframe?: opts.skip_until_keyframe?,
      skip_until_parameters?: opts.skip_until_parameters?,
      metadata: nil,
      acc: <<>>
    }

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
    payload = state.partial_frame <> buffer.payload

    case carries_parameters_in_band?(payload) do
      {:ok, carries_params?} ->
        payload =
          if carries_params?,
            # If the stream carries parameters in-band, don't add the frame prefix. In-band parameters take priority
            do: payload,
            # Frame appeared without SPS and PPS, we need to insert them
            else: state.frame_prefix <> payload

        buffer = %Buffer{buffer | payload: payload}
        # Frame prefix can always be discarded - we either inserted it or we don't need it at all
        do_process(buffer, %{state | frame_prefix: <<>>, partial_frame: <<>>})

      {:error, :not_enough_data} ->
        {:ok, %{state | partial_frame: payload}}
    end
  end

  defp do_process(%Buffer{payload: payload} = buffer, state) do
    case Native.parse(payload, state.parser_ref) do
      {:ok, sizes, decoding_order_numbers, presentation_order_numbers, resolution_changes} ->
        metadata = %{buffer_metadata: buffer.metadata, pts: buffer.pts, dts: buffer.dts}

        {bufs, state} =
          parse_access_units(
            payload,
            sizes,
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

  # analize resolution changes and generate appropriate caps before corresponding buffers
  defp parse_resolution_changes(state, bufs, resolution_changes, acc \\ [], index_offset \\ 0)

  defp parse_resolution_changes(state, [], [], [], _index_offset) do
    {[], state}
  end

  defp parse_resolution_changes(state, bufs, [], [], _index_offset) do
    # When this is the first call to parse_resolution_changes
    # with bufs but without resolution changes,
    # check whether we have pending caps and if yes, send them with buffers
    caps =
      if state.pending_caps != nil do
        [caps: {:output, state.pending_caps}]
      else
        []
      end

    actions = caps ++ [buffer: {:output, bufs}]
    {actions, %{state | pending_caps: nil}}
  end

  defp parse_resolution_changes(state, bufs, [], acc, _index_offset) do
    actions =
      ([buffer: {:output, bufs}] ++ acc)
      |> Enum.reverse()

    {actions, state}
  end

  defp parse_resolution_changes(state, [], res_changes, [], _index_offset) do
    # When this is the first call to parse_resolution_changes
    # with some resolution changes but without bufs (e.g. because of waiting for a keyframe),
    # cache new caps as pending. We will send them when new buffers appear
    meta = List.last(res_changes)
    caps = mk_caps(state, meta.width, meta.height)
    {[], %{state | pending_caps: caps}}
  end

  defp parse_resolution_changes(state, bufs, [meta | resolution_changes], acc, index_offset) do
    updated_index = meta.index - index_offset
    {old_bufs, next_bufs} = Enum.split(bufs, updated_index)
    next_caps = mk_caps(state, meta.width, meta.height)

    caps = [caps: {:output, next_caps}]

    buffers_before_change =
      case old_bufs do
        [] -> []
        _non_empty -> [buffer: {:output, old_bufs}]
      end

    pending_caps =
      if state.pending_caps != nil and buffers_before_change != [] do
        [caps: {:output, state.pending_caps}]
      else
        []
      end

    parse_resolution_changes(
      %{state | pending_caps: nil},
      next_bufs,
      resolution_changes,
      caps ++ buffers_before_change ++ pending_caps ++ acc,
      meta.index
    )
  end

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
  def handle_end_of_stream(:input, _ctx, state) do
    with {:ok, sizes, decoding_order_numbers, presentation_order_numbers} <-
           Native.flush(state.parser_ref) do
      {bufs, state} =
        parse_access_units(
          <<>>,
          sizes,
          state.metadata,
          decoding_order_numbers,
          presentation_order_numbers,
          state
        )

      if state.partial_frame != <<>> do
        Membrane.Logger.warn("Discarding incomplete frame because of end of stream")
      end

      actions = [buffer: {:output, bufs}, end_of_stream: :output]
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
         [au_size | au_sizes],
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

        dts = div(decoding_order_number * seconds * Membrane.Time.second(), frames)
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
            %Buffer{
              pts: pts,
              dts: dts,
              payload: au,
              metadata: put_in(au_metadata, [:h264, :nalus], nalus)
            }
          ]

        %{alignment: :au, attach_nalus?: false} ->
          [%Buffer{pts: pts, dts: dts, payload: au, metadata: au_metadata}]

        %{alignment: :nal} ->
          Enum.map(nalus, fn nalu ->
            %Buffer{
              pts: pts,
              dts: dts,
              payload: :binary.part(au, nalu.prefixed_poslen),
              metadata: Map.merge(metadata.buffer_metadata, nalu.metadata)
            }
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

    %H264{
      width: width,
      height: height,
      framerate: state.framerate || {0, 1},
      alignment: state.alignment,
      nalu_in_metadata?: state.attach_nalus?,
      stream_format: :byte_stream,
      profile: profile
    }
  end

  # Checks if the required parameter NALus (see @required_parameter_nalus) are present in-band before any video frames appear
  defp carries_parameters_in_band?(payload) do
    types =
      payload
      |> NALu.parse()
      |> elem(0)
      |> Enum.map(& &1.metadata.h264.type)

    # Split NALus parsed from the payload into two sections: parameters and data.
    # If data appears before required parameters, this would cause an error in FFmpeg,
    # so we identify the stream as not carrying parameters in-band.
    # In such a case, they will be inserted into the stream before parsing,
    # assuming that H264.RemoteStream caps providing them are present
    {parameter_nalus, data_nalus} = Enum.split_while(types, &is_allowed_before_data/1)

    parameter_nalus_set = MapSet.new(parameter_nalus)

    has_required_parameters? =
      @required_parameter_nalus |> Enum.all?(&MapSet.member?(parameter_nalus_set, &1))

    cond do
      has_required_parameters? ->
        {:ok, true}

      data_nalus == [] ->
        {:error, :not_enough_data}

      true ->
        {:ok, false}
    end
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
