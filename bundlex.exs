defmodule Membrane.H264.FFmpeg.BundlexProject do
  use Bundlex.Project

  defmodule PrecompiledFFmpeg do
    use Bundlex.PrecompiledDependency

    @impl true
    def get_build_url({_architecture, _vendor, "linux"}) do
      "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n4.4-latest-linux64-gpl-shared-4.4.tar.xz/"
    end

    @impl true
    def get_build_url({_architecture, _vendor, darwin_os_name}) do
      if String.starts_with?(darwin_os_name, "darwin") do
        "https://github.com/membraneframework-labs/precompiled_ffmpeg/releases/download/version1/ffmpeg_macos.tar.gz"
      else
        :unavailable
      end
    end

    @impl true
    def get_build_url(_unknown_target) do
      :unavailable
    end

    @impl true
    def get_headers_path(path, _target) do
      "#{path}/include"
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
          {PrecompiledFFmpeg, ["libavcodec", "libswresample", "libavutil"]}
        ],
        preprocessor: Unifex
      ],
      decoder: [
        interface: :nif,
        sources: ["decoder.c"],
        os_deps: [
          {PrecompiledFFmpeg, ["libavcodec", "libswresample", "libavutil"]}
        ],
        preprocessor: Unifex
      ],
      encoder: [
        interface: :nif,
        sources: ["encoder.c"],
        os_deps: [
          {PrecompiledFFmpeg, ["libavcodec", "libswresample", "libavutil"]}
        ],
        preprocessor: Unifex
      ]
    ]
  end
end
