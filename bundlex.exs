defmodule Membrane.H264.FFmpeg.BundlexProject do
  use Bundlex.Project

  defp get_ffmpeg() do
    case Bundlex.get_target() do
      %{os: "linux"} ->
        {:precompiled,
         "https://github.com/membraneframework-precompiled/precompiled_ffmpeg/releases/download/version1/ffmpeg_linux.tar.gz"}

      %{architecture: "x86_64", os: "darwin" <> _rest_of_os_name} ->
        {:precompiled,
         "https://github.com/membraneframework-precompiled/precompiled_ffmpeg/releases/download/version1/ffmpeg_macos_intel.tar.gz"}

      _other ->
        nil
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
          {[get_ffmpeg(), :pkg_config], ["libavcodec", "libswresample", "libavutil"]}
        ],
        preprocessor: Unifex
      ],
      decoder: [
        interface: :nif,
        sources: ["decoder.c"],
        os_deps: [
          {[get_ffmpeg(), :pkg_config], ["libavcodec", "libswresample", "libavutil"]}
        ],
        preprocessor: Unifex
      ],
      encoder: [
        interface: :nif,
        sources: ["encoder.c"],
        os_deps: [
          {[get_ffmpeg(), :pkg_config], ["libavcodec", "libswresample", "libavutil"]}
        ],
        preprocessor: Unifex
      ]
    ]
  end
end
