defmodule Membrane.H264.FFmpeg.BundlexProject do
  use Bundlex.Project

  defp get_ffmpeg() do
    case Bundlex.get_target() do
      {_architecture, _vendor, "linux"} ->
        "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n4.4-latest-linux64-gpl-shared-4.4.tar.xz/"

      {_architecture, _vendor, "darwin" <> _rest_of_os_name} ->
        "https://github.com/membraneframework-labs/precompiled_ffmpeg/releases/download/version1/ffmpeg_macos.tar.gz"

      _other ->
        :unavailable
    end
  end

  def project() do
    [
      natives: natives()
    ]
  end

  defp natives() do
    [
      parser: [
        interface: :nif,
        sources: ["parser.c"],
        os_deps: [
          {get_ffmpeg(), ["libavcodec", "libswresample", "libavutil"]}
        ],
        preprocessor: Unifex
      ],
      decoder: [
        interface: :nif,
        sources: ["decoder.c"],
        os_deps: [
          {get_ffmpeg(), ["libavcodec", "libswresample", "libavutil"]}
        ],
        preprocessor: Unifex
      ],
      encoder: [
        interface: :nif,
        sources: ["encoder.c"],
        os_deps: [
          {get_ffmpeg(), ["libavcodec", "libswresample", "libavutil"]}
        ],
        preprocessor: Unifex
      ]
    ]
  end
end
