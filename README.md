# Membrane Multimedia Framework: FFmpeg H264 Element

[![CircleCI](https://circleci.com/gh/membraneframework/membrane-element-ffmpeg-h264.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane-element-ffmpeg-h264)

This package provides [Membrane Multimedia Framework](https://membraneframework.org)
elements that can be used to encode, parse and decode H264 video streams using [ffmpeg](https://www.ffmpeg.org)
and [x264](https://www.videolan.org/developers/x264.html)

Documentation is available at [HexDocs](https://hexdocs.pm/membrane_element_ffmpeg_h264/)


## Installation

Add the following line to your `deps` in `mix.exs`. Run `mix deps.get`.

```elixir
{:membrane_element_ffmpeg_h264, "~> 0.2.0"}
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

## Copyright and License

Copyright 2018, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)
