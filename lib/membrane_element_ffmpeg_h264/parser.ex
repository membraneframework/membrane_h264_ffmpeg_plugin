defmodule Membrane.Element.FFmpeg.H264.Parser do
  use Membrane.Element.Base.Filter
  alias __MODULE__.Native
  alias Membrane.Buffer
  alias Membrane.Event.EndOfStream

  def_input_pads input: [
                   demand_unit: :buffers,
                   caps: :any
                 ]

  def_output_pads output: [
                    # TODO: add h264 caps
                    caps: :any
                  ]

  @impl true
  def handle_init(_) do
    {:ok, %{parser_ref: nil, partial_frame: "", unparsed: ""}}
  end

  @impl true
  def handle_stopped_to_prepared(_, state) do
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
  def handle_process(:input, %Buffer{payload: payload}, _, state) do
    # TODO: Check if 'unparsed' is needed
    %{parser_ref: parser_ref, partial_frame: partial_frame, unparsed: unparsed} = state

    with {:ok, sizes, consumed_bytes} <- Native.parse(unparsed <> payload, parser_ref),
         {bufs, rest} <- gen_bufs_by_sizes(partial_frame <> payload, sizes) do
      <<_::bytes-size(consumed_bytes), unparsed::binary>> = payload
      state = %{state | partial_frame: rest, unparsed: unparsed}
      {{:ok, buffer: {:output, bufs}, redemand: :output}, state}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  @impl true
  def handle_event(:input, %EndOfStream{}, _ctx, state) do
    %{parser_ref: parser_ref, partial_frame: partial_frame} = state

    with {:ok, sizes} <- Native.flush(parser_ref),
         {bufs, rest} <- gen_bufs_by_sizes(partial_frame, sizes) do
      if rest != "" do
        # warn
      end

      state = %{state | partial_frame: ""}
      {{:ok, buffer: {:output, bufs}, event: {:output, %EndOfStream{}}}, state}
    end
  end

  def handle_event(:input, event, _ctx, state) do
    {{:ok, event: {:output, event}}, state}
  end

  @impl true
  def handle_prepared_to_stopped(_, state) do
    {:ok, %{state | parser_ref: nil}}
  end

  defp gen_bufs_by_sizes(input, sizes) do
    Enum.map_reduce(sizes, input, fn size, stream ->
      <<frame::bytes-size(size), rest::binary>> = stream
      {%Buffer{payload: frame}, rest}
    end)
  end
end
