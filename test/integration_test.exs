defmodule IntegrationTest.TestingPipeline.H264 do
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

defmodule IntegrationTest do
  alias __MODULE__.TestingPipeline.H264
  alias Membrane.Pipeline
  use ExUnit.Case

  def prepare_paths(filename) do
    in_path = "fixtures/input-#{filename}.h264" |> Path.expand(__DIR__)
    reference_path = "fixtures/reference-#{filename}.raw" |> Path.expand(__DIR__)
    out_path = "/tmp/output-#{filename}.raw"
    File.rm(out_path)
    {in_path, reference_path, out_path}
  end

  def assert_files_equal(file_a, file_b) do
    assert {:ok, a} = File.read(file_a)
    assert {:ok, b} = File.read(file_b)
    assert a == b
  end

  test "decode 10 720p frames" do
    {in_path, ref_path, out_path} = prepare_paths("10-720p")
    {:ok, pid} = Pipeline.start_link(H264, %{in: in_path, out: out_path, pid: self()}, [])
    assert Pipeline.play(pid) == :ok
    assert_receive :eos, 500
    assert_files_equal(out_path, ref_path)
  end

  test "decode 100 240p frames" do
    {in_path, ref_path, out_path} = prepare_paths("100-240p")
    {:ok, pid} = Pipeline.start_link(H264, %{in: in_path, out: out_path, pid: self()}, [])
    assert Pipeline.play(pid) == :ok
    assert_receive :eos, 1000
    assert_files_equal(out_path, ref_path)
  end
end
