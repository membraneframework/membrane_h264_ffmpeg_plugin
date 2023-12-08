defmodule Membrane.H264.FFmpeg.BundlexProject do
  use Bundlex.Project

  defp get_ffmpeg() do
    membrane_precompiled_url_prefix =
      "https://github.com/membraneframework-precompiled/precompiled_ffmpeg/releases/latest/download/ffmpeg"

    membrane_precompiled_url =
      case Bundlex.get_target() do
        %{os: "linux", vendor: "alpine"} ->
          nil

        %{architecture: "aarch64", os: "linux"} ->
          "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n6.0-latest-linuxarm64-gpl-shared-6.0.tar.xz"

        %{os: "linux"} ->
          "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n6.0-latest-linux64-gpl-shared-6.0.tar.xz"

        %{architecture: "x86_64", os: "darwin" <> _rest_of_os_name} ->
          "#{membrane_precompiled_url_prefix}_macos_intel.tar.gz"

        %{architecture: "aarch64", os: "darwin" <> _rest_of_os_name} ->
          "#{membrane_precompiled_url_prefix}_macos_arm.tar.gz"

        _other ->
          nil
      end

      if membrane_precompiled_url != nil do
        [
          {:precompiled, get_ffmpeg_url(), ["libavcodec", "libavutil"]},
          {:pkg_config, ["libavcodec", "libavutil"]}
        ]
      else
        [
          {:pkg_config, ["libavcodec", "libavutil"]}
        ]
      end
  end

  def project() do
    [
      natives: natives()
    ]
  end

  defp natives() do
    [
      decoder: [
        interface: :nif,
        sources: ["decoder.c"],
        os_deps: [
          ffmpeg: get_ffmpeg()
        ],
        preprocessor: Unifex
      ],
      encoder: [
        interface: :nif,
        sources: ["encoder.c"],
        os_deps: [
          ffmpeg: get_ffmpeg()
        ],
        preprocessor: Unifex
      ]
    ]
  end
end
