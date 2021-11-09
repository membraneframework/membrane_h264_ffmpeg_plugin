defmodule Membrane.H264.FFmpeg.Common do
  @moduledoc false
  use Ratio
  @h264_time_base 90_000

  @doc """
  Converts time in membrane time base (1 [ns]) to h264 time base (1/90_000 [s])
  """
  @spec to_h264_time_base_truncated(number | Ratio.t()) :: integer
  def to_h264_time_base_truncated(timestamp) do
    (timestamp * @h264_time_base / Membrane.Time.second()) |> trunc()
  end

  @doc """
  Converts time from h264 time base (1/90_000 [s]) to membrane time base (1 [ns])
  """
  @spec to_membrane_time_base_truncated(number | Ratio.t()) :: integer
  def to_membrane_time_base_truncated(timestamp) do
    timestamp * Membrane.Time.second() / @h264_time_base
  end
end
