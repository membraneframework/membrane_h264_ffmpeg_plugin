defmodule Membrane.Element.FFmpeg.H264.Decoder do
  use Membrane.Element.Base.Filter
  alias __MODULE__.Native
  alias Membrane.Buffer
  alias Membrane.Event.EndOfStream
  use Bunch

  def_input_pads input: [
                   demand_unit: :buffers,
                   # TODO: add h264 caps
                   caps: :any
                 ]

  def_output_pads output: [
                    # TODO: add h264 caps
                    caps: :any
                  ]

  @impl true
  def handle_init(_) do
    %{decoder_ref: nil}
  end

  @impl true
  def handle_stopped_to_prepared(_, state) do
    with {:ok, decoder_ref} <- Native.create() do
      {:ok, %{decoder_ref: decoder_ref}}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: payload}, _, state) do
    %{decoder_ref: decoder_ref} = state

    with {:ok, frames} <- Native.decode(payload, decoder_ref),
         bufs <- wrap_frames(frames) do
      {{:ok, bufs ++ [redemand: :output]}, state}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  @impl true
  def handle_event(:input, %EndOfStream{}, _ctx, state) do
    with {:ok, frames} <- Native.flush(state.decoder_ref),
         bufs <- wrap_frames(frames) do
      {{:ok, bufs}, state}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  @impl true
  def handle_prepared_to_stopped(_, state) do
    {:ok, %{state | decoder_ref: nil}}
  end

  defp wrap_frames([]), do: []

  defp wrap_frames(frames) do
    frames |> Enum.map(fn frame -> %Buffer{payload: frame} end) ~> [buffer: {:output, &1}]
  end
end
