defmodule DecodingPipeline do
  @moduledoc false

  use Membrane.Pipeline
  alias Membrane.Element

  def handle_init(%{in: in_path, out: out_path, pid: pid}) do
    children = [
      file_src: %Element.File.Source{chunk_size: 40_960, location: in_path},
      parser: Element.FFmpeg.H264.Parser,
      decoder: Element.FFmpeg.H264.Decoder,
      sink: %Element.File.Sink{location: out_path}
    ]

    links = %{
      {:file_src, :output} => {:parser, :input},
      {:parser, :output} => {:decoder, :input},
      {:decoder, :output} => {:sink, :input}
    }

    spec = %Membrane.Pipeline.Spec{
      children: children,
      links: links
    }

    {{:ok, spec}, %{pid: pid}}
  end

  def handle_message(%Membrane.Message{type: :end_of_stream}, _name, %{pid: pid} = state) do
    send(pid, :eos)
    {:ok, state}
  end
end
