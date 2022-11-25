defmodule Membrane.H264.FFmpeg.Parser.Native do
  @moduledoc false
  use Unifex.Loader

  @spec get_profile!(reference()) :: Membrane.H264.profile_t()
  def get_profile!(parser_ref) do
    case get_profile(parser_ref) do
      {:error, reason} -> raise "Failed to obtain profile from native parser: #{inspect(reason)}"
      {:ok, :unknown} -> raise "Unknown H264 profile!"
      {:ok, profile} -> profile
    end
  end
end
