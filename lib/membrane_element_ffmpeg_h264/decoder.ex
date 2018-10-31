defmodule Membrane.Element.FFmpeg.H264.Decoder do
  @moduledoc """
  Membrane element that decodes video in H264 format. It is backed by decoder from FFmpeg.

  The element expects the data for each frame (Access Unit) to be received in a separate buffer,
  so the parser (`Membrane.Element.RawVideo.Parser`) may be required in a pipeline before
  decoder (e.g. when input is read from `Membrane.Element.File.Source`).
  """
  use Membrane.Element.Base.Filter
  alias __MODULE__.Native
  alias Membrane.Buffer
  alias Membrane.Event.EndOfStream
  alias Membrane.Caps.Video.{H264, Raw}
  use Bunch

  def_input_pads input: [
                   demand_unit: :buffers,
                   caps: {H264, stream_format: :byte_stream, alignment: :au}
                 ]

  def_output_pads output: [
                    caps: {Raw, format: one_of([:I420, :I422]), aligned: true}
                  ]

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
  def handle_process(:input, %Buffer{payload: payload}, ctx, state) do
    %{decoder_ref: decoder_ref} = state

    with {:ok, frames} <- Native.decode(payload, decoder_ref),
         bufs = wrap_frames(frames),
         in_caps = ctx.pads.input.caps,
         out_caps = ctx.pads.output.caps,
         {:ok, caps} <- get_caps_if_needed(in_caps, out_caps, decoder_ref) do
      # redemand actually makes sense only for the first call (because decoder keeps 2 frames buffered)
      # but it is noop otherwise, so there is no point in implementing special logic for that case
      actions = Enum.concat([caps, bufs, [redemand: :output]])
      {{:ok, actions}, state}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  @impl true
  def handle_caps(:input, _caps, _ctx, state) do
    # ignoring caps, new ones will be generated from decoder metadata
    {:ok, state}
  end

  @impl true
  def handle_event(:input, %EndOfStream{}, _ctx, state) do
    with {:ok, frames} <- Native.flush(state.decoder_ref),
         bufs <- wrap_frames(frames) do
      actions = bufs ++ [event: {:output, %EndOfStream{}}, notify: {:end_of_stream, :input}]
      {{:ok, actions}, state}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  def handle_event(:input, event, ctx, state) do
    super(:input, event, ctx, state)
  end

  @impl true
  def handle_prepared_to_stopped(_ctx, state) do
    {:ok, %{state | decoder_ref: nil}}
  end

  defp wrap_frames([]), do: []

  defp wrap_frames(frames) do
    frames |> Enum.map(fn frame -> %Buffer{payload: frame} end) ~> [buffer: {:output, &1}]
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
end
