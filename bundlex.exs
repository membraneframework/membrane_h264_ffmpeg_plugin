defmodule Membrane.H264.FFmpeg.BundlexProject do
  use Bundlex.Project

  defp get_ffmpeg_url() do
    url_prefix =
      "https://github.com/membraneframework-precompiled/precompiled_ffmpeg/releases/latest/download/ffmpeg"

    case Bundlex.get_target() do
      %{os: "linux"} ->
        {:precompiled, "#{url_prefix}_linux.tar.gz"}

      %{architecture: "x86_64", os: "darwin" <> _rest_of_os_name} ->
        {:precompiled, "#{url_prefix}_macos_intel.tar.gz"}

      %{architecture: "aarch64", os: "darwin" <> _rest_of_os_name} ->
        {:precompiled, "#{url_prefix}_macos_arm.tar.gz"}

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
          {get_ffmpeg_url(), ["libavcodec", "libavutil"]}
        ],
        preprocessor: Unifex
      ],
      decoder: [
        interface: :nif,
        sources: ["decoder.c"],
        os_deps: [
          {get_ffmpeg_url(), ["libavcodec", "libavutil"]}
        ],
        preprocessor: Unifex
      ],
      encoder: [
        interface: :nif,
        sources: ["encoder.c"],
        os_deps: [
          {get_ffmpeg_url(), ["libavcodec", "libavutil"]}
        ],
        preprocessor: Unifex
      ]
    ]
  end
end
