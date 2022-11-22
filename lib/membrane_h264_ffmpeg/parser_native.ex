defmodule Membrane.H264.FFmpeg.Parser.Native do
  @moduledoc false
  use Unifex.Loader

  @spec get_profile!(reference()) :: String.t()
  def get_profile!(parser_ref) do
    case get_profile(parser_ref) do
      {:ok, profile} -> profile
      {:error, reason} -> raise "Failed to obtain profile from native parser: #{inspect(reason)}"
    end
  end
end
