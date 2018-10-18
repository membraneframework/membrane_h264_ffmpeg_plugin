defmodule Membrane.Element.FFmpeg.H264.Encoder do
  use Membrane.Element.Base.Filter
  alias __MODULE__.Native
  alias Membrane.Buffer
  alias Membrane.Event.EndOfStream
  alias Membrane.Caps.Video.{H264, Raw}
  use Bunch
  use Bunch.Typespec

  def_input_pads input: [
                   demand_unit: :buffers,
                   caps: {Raw, format: :I420, aligned: true}
                 ]

  def_output_pads output: [
                    caps: {H264, stream_format: :byte_stream, alignment: :au}
                  ]

  @default_crf 23

  @list_type presets :: [
               :ultrafast,
               :superfast,
               :veryfast,
               :faster,
               :fast,
               :medium,
               :slow,
               :slower,
               :veryslow,
               :placebo
             ]

  def_options crf: [
                description: """
                Constant rate factor that affects the quality of output stream.
                Value of 0 is lossless compression while 51 (for 8-bit samples)
                or 63 (10-bit) offers the worst quality.

                The range is exponential, so increasing the CRF value +6 results in
                roughly half the bitrate / file size, while -6 leads to roughly twice the bitrate.
                """,
                type: :int,
                default: @default_crf
              ],
              preset: [
                description: """
                Collection of predefined options providing certain encoding. The slower the
                preset choosen, the higher compression for the same quality can be achieved.
                """,
                type: :atom,
                spec: presets(),
                default: :medium
              ],
              profile: [
                description: """
                Defines the features that will have to be supported by decoder to decode this video.
                """,
                type: :atom,
                spec: H264.profile_t(),
                default: :high
              ]

  @impl true
  def handle_init(opts) do
    {:ok, opts |> Map.merge(%{encoder_ref: nil})}
  end

  @impl true
  def handle_demand(:output, _, :buffers, _ctx, %{encoder_ref: nil} = state) do
    # Wait until we have encoder
    {:ok, state}
  end

  def handle_demand(:output, size, :buffers, _ctx, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: payload}, ctx, state) do
    %{encoder_ref: encoder_ref} = state

    with {:ok, frames} <- Native.encode(payload, encoder_ref),
         bufs <- wrap_frames(frames),
         in_caps <- ctx.caps.(:input) do
      caps = [
        caps:
          {:output,
           %H264{
             alignment: :au,
             framerate: in_caps.framerate,
             height: in_caps.height,
             width: in_caps.width,
             profile: state.profile,
             stream_format: :byte_stream
           }}
      ]

      actions = Enum.concat([caps, bufs, [redemand: :output]])
      {{:ok, actions}, state}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  @impl true
  def handle_caps(:input, %Raw{} = caps, _ctx, state) do
    {framerate_num, framerate_denom} = caps.framerate

    with {:ok, encoder_ref} <-
           Native.create(
             caps.width,
             caps.height,
             caps.format,
             state.preset,
             state.profile,
             framerate_num,
             framerate_denom,
             state.crf
           ) do
      {:ok, %{state | encoder_ref: encoder_ref}}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  @impl true
  def handle_event(:input, %EndOfStream{}, _ctx, state) do
    with {:ok, frames} <- Native.flush(state.encoder_ref),
         bufs <- wrap_frames(frames) do
      {{:ok, bufs ++ [event: {:output, %EndOfStream{}}]}, state}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  def handle_event(:input, event, _ctx, state) do
    {{:ok, event: {:output, event}}, state}
  end

  @impl true
  def handle_prepared_to_stopped(_, state) do
    {:ok, %{state | encoder_ref: nil}}
  end

  defp wrap_frames([]), do: []

  defp wrap_frames(frames) do
    frames |> Enum.map(fn frame -> %Buffer{payload: frame} end) ~> [buffer: {:output, &1}]
  end
end
