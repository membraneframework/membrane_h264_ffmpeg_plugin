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
  alias Membrane.H264.FFmpeg.Common

  require Membrane.Logger

  @no_pts -9_223_372_036_854_775_808

  def_options use_shm?: [
                type: :boolean,
                desciption:
                  "If true, native decoder will use shared memory (via `t:Shmex.t/0`) for storing frames",
                default: false
              ]

  def_input_pad :input,
    demand_unit: :buffers,
    caps: {H264, stream_format: :byte_stream, alignment: :au}

  def_output_pad :output,
    caps: {Raw, format: one_of([:I420, :I422]), aligned: true}

  @impl true
  def handle_init(opts) do
    state = %{decoder_ref: nil, caps_changed: false, use_shm?: opts.use_shm?}
    {:ok, state}
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
  def handle_process(:input, buffer, ctx, state) do
    %{decoder_ref: decoder_ref, use_shm?: use_shm?} = state

    dts = if(buffer.dts, do: Common.to_h264_time_base_truncated(buffer.dts), else: @no_pts)
    pts = if(buffer.pts, do: Common.to_h264_time_base_truncated(buffer.pts), else: @no_pts)

    with {:ok, pts_list_h264_base, frames} <-
           Native.decode(
             buffer.payload,
             pts,
             dts,
             use_shm?,
             decoder_ref
           ),
         bufs = wrap_frames(pts_list_h264_base, frames),
         in_caps = ctx.pads.input.caps do
      {caps, state} = update_caps_if_needed(state, in_caps)

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
    # only redeclaring decoder - new caps will be generated in handle_process, after decoding key_frame
    with {:ok, decoder_ref} <- Native.create() do
      {{:ok, redemand: :output}, %{state | decoder_ref: decoder_ref, caps_changed: true}}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    with {:ok, best_effort_pts_list, frames} <-
           Native.flush(state.use_shm?, state.decoder_ref),
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

  defp wrap_frames(pts_list, frames) do
    Enum.zip(pts_list, frames)
    |> Enum.map(fn {pts, frame} ->
      %Buffer{pts: Common.to_membrane_time_base_truncated(pts), payload: frame}
    end)
    |> then(&[buffer: {:output, &1}])
  end

  defp update_caps_if_needed(%{caps_changed: true, decoder_ref: decoder_ref} = state, in_caps) do
    {[caps: {:output, generate_caps(in_caps, decoder_ref)}], %{state | caps_changed: false}}
  end

  defp update_caps_if_needed(%{caps_changed: false} = state, _in_caps) do
    {[], state}
  end

  defp generate_caps(input_caps, decoder_ref) do
    {:ok, width, height, pix_fmt} = Native.get_metadata(decoder_ref)

    framerate =
      case input_caps do
        nil -> {0, 1}
        %H264{framerate: in_framerate} -> in_framerate
      end

    %Raw{
      aligned: true,
      format: pix_fmt,
      framerate: framerate,
      height: height,
      width: width
    }
  end
end
