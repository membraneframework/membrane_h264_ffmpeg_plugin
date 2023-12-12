defmodule Membrane.H264.FFmpeg.BundlexProject do
  use Bundlex.Project

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
          ffmpeg: [
            {:precompiled, Membrane.PrecompiledDependencyProvider.get_dependency_url(:ffmpeg),
             ["libavcodec", "libavutil"]},
            {:pkg_config, ["libavcodec", "libavutil"]}
          ]
        ],
        preprocessor: Unifex
      ],
      encoder: [
        interface: :nif,
        sources: ["encoder.c"],
        os_deps: [
          ffmpeg: [
            {:precompiled, Membrane.PrecompiledDependencyProvider.get_dependency_url(:ffmpeg),
             ["libavcodec", "libavutil"]},
            {:pkg_config, ["libavcodec", "libavutil"]}
          ]
        ],
        preprocessor: Unifex
      ]
    ]
  end
end
