defmodule Membrane.H264.FFmpeg.Decoder do
  @moduledoc """
  Membrane element that decodes video in H264 format. It is backed by decoder from FFmpeg.

  The element expects the data for each frame (Access Unit) to be received in a separate buffer,
  so the parser (`Membrane.H264.FFmpeg.Parser`) may be required in a pipeline before
  decoder (e.g. when input is read from `Membrane.File.Source`).
  """
  use Membrane.Filter
  alias __MODULE__.Native
  alias Membrane.Buffer
  alias Membrane.Caps.Video.{H264, Raw}
  use Bunch

  @h264_time_base 90_000

  def_options add_dts: [
                spec: boolean(),
                default: false,
                description: """
                Setting this flag to true causes decoder to add presentation timestamp (pts) taken from buffer timestamp into the AVPacket and in consequence to the produced frame.
                """
              ]

  def_input_pad :input,
    demand_unit: :buffers,
    caps: {H264, stream_format: :byte_stream, alignment: :au}

  def_output_pad :output,
    caps: {Raw, format: one_of([:I420, :I422]), aligned: true}

  @impl true
  def handle_init(_opts) do
    {:ok, %{decoder_ref: nil}}
  end

  @impl true
  def handle_stopped_to_prepared(_ctx, state) do
    with {:ok, decoder_ref} <- Native.create() do
      {:ok, %{state | decoder_ref: decoder_ref}}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_process(:input, %Buffer{metadata: metadata, payload: payload}, ctx, state) do
    %{decoder_ref: decoder_ref} = state
    dts = metadata[:dts] || 0

    with {:ok, best_effort_pts_list_h264_base, frames} <-
           Native.decode_with_dts(payload, to_h264_time_base(dts), decoder_ref),
         best_effort_pts_list =
           Enum.map(best_effort_pts_list_h264_base, &to_membrane_time_base(&1)),
         bufs = wrap_frames(best_effort_pts_list, frames),
         in_caps = ctx.pads.input.caps,
         out_caps = ctx.pads.output.caps,
         {:ok, caps} <- get_caps_if_needed(in_caps, out_caps, decoder_ref) do
      # redemand actually makes sense only for the first call (because decoder keeps 2 frames buffered)
      # but it is noop otherwise, so there is no point in implementing special logic for that case
      actions = Enum.concat([caps, bufs, [redemand: :output]])

      {{:ok, actions}, state}
    else
      {:error, reason} ->
        {{:error, reason}, state}
    end
  end

  @impl true
  def handle_caps(:input, _caps, _ctx, state) do
    # ignoring caps, new ones will be generated from decoder metadata
    {:ok, state}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    with {:ok, best_effort_pts_list, frames} <- Native.flush(state.decoder_ref),
         bufs <- wrap_frames(best_effort_pts_list, frames) do
      actions = bufs ++ [end_of_stream: :output, notify: {:end_of_stream, :input}]
      {{:ok, actions}, state}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  @impl true
  def handle_prepared_to_stopped(_ctx, state) do
    {:ok, %{state | decoder_ref: nil}}
  end

  defp wrap_frames([], []), do: []

  defp wrap_frames(best_effort_pts_list, frames) do
    Enum.zip(best_effort_pts_list, frames)
    |> Enum.map(fn {best_effort_pts, frame} ->
      %Buffer{metadata: %{pts: best_effort_pts}, payload: frame}
    end)
    ~> [buffer: {:output, &1}]
  end

  defp get_caps_if_needed(input_caps, nil, decoder_ref) do
    with {:ok, width, height, pix_fmt} <- Native.get_metadata(decoder_ref) do
      framerate =
        case input_caps do
          nil -> {0, 1}
          %H264{framerate: in_framerate} -> in_framerate
        end

      caps = %Raw{
        aligned: true,
        format: pix_fmt,
        framerate: framerate,
        height: height,
        width: width
      }

      {:ok, caps: {:output, caps}}
    end
  end

  defp get_caps_if_needed(_, _, _), do: {:ok, []}

  # decoder requires timestamps in h264 time base, that is 1/90_000 [s]
  # timestamps produced by this function are passed to the decoder so
  # they must be integers
  defp to_h264_time_base(timestamp) do
    div(timestamp * @h264_time_base, Membrane.Time.second())
  end

  # all timestamps in membrane should be represented in the internal units, that is 1 [ns]
  # this function can return rational number
  defp to_membrane_time_base(timestamp) do
    Ratio.div(timestamp * Membrane.Time.second(), @h264_time_base)
  end
end
