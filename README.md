# Membrane H264 FFmpeg plugin

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_h264_ffmpeg_plugin.svg)](https://hex.pm/packages/membrane_h264_ffmpeg_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_h264_ffmpeg_plugin/)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_h264_ffmpeg_plugin.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_h264_ffmpeg_plugin)

This package provides H264 video parser, decoder and encoder, based on [ffmpeg](https://www.ffmpeg.org)
and [x264](https://www.videolan.org/developers/x264.html).

It is a part of the [Membrane Multimedia Framework](https://membraneframework.org)

Documentation is available at [HexDocs](https://hexdocs.pm/membrane_h264_ffmpeg_plugin/)

## Installation

Add the following line to your `deps` in `mix.exs`. Run `mix deps.get`.

```elixir
  {:membrane_h264_ffmpeg_plugin, "~> 0.21.5"}
```

You also need to have [ffmpeg](https://www.ffmpeg.org) libraries installed in your system.

### Ubuntu

```bash
sudo apt-get install libavcodec-dev libavformat-dev libavutil-dev
```

### Arch/Manjaro

```bash
pacman -S ffmpeg
```

### MacOS

```bash
brew install ffmpeg
```

## Usage Example

### Decoder

The following pipeline takes 30fps H264 file and decodes it to the raw video.

```elixir
defmodule Decoding.Pipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_) do
    children = [
      source: %Membrane.File.Source{chunk_size: 40_960, location: "input.h264"},
      parser: %H264.FFmpeg.Parser{framerate: {30, 1}},
      decoder: H264.FFmpeg.Decoder,
      sink: %Membrane.File.Sink{location: "output.raw"}
    ]

    links = [
      link(:source)
      |> to(:parser)
      |> to(:decoder)
      |> to(:sink)
    ]

    {{:ok, spec: %ParentSpec{children: children, links: links}}, %{}}
  end
end
```

### Encoder

The following pipeline takes 720p raw video file as input and encodes it as H264.

```elixir
defmodule Encoding.Pipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_) do
    children = [
      source: %Membrane.File.Source{chunk_size: 40_960, location: "input.raw"},
      parser: %Membrane.RawVideo.Parser{width: 1280, height: 720, pixel_format: :I420},
      encoder: %Membrane.H264.FFmpeg.Encoder{preset: :fast, crf: 30},
      sink: %Membrane.File.Sink{location: "output.h264"}
    ]

    links = [
      link(:source)
      |> to(:parser)
      |> to(:encoder)
      |> to(:sink)
    ]

    {{:ok, spec: %ParentSpec{children: children, links: links}}, %{}}
  end
end
```

## Copyright and License

Copyright 2018, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)
