# Membrane Multimedia Framework: FFmpeg H264 Element

[![Build Status](https://travis-ci.com/membraneframework/membrane-element-ffmpeg-h264.svg?branch=master)](https://travis-ci.com/membraneframework/membrane-element-ffmpeg-h264)

This package provides [Membrane Multimedia Framework](https://membraneframework.org)
elements that can be used to encode and decode H264 video streams using [ffmpeg](https://www.ffmpeg.org)
and [x264](https://www.videolan.org/developers/x264.html)

Documentation is available at [HexDocs](https://hexdocs.pm/membrane_element_ffmpeg_h264/)


## Installation

Add the following line to your `deps` in `mix.exs`. Run `mix deps.get`.

```elixir
{:membrane_element_ffmpeg_h264, "~> 0.1"}
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

