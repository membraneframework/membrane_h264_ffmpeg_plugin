defmodule Membrane.Element.FFmpeg.H264.BundlexProject do
  use Bundlex.Project

  def project() do
    [
      nifs: nifs(Bundlex.platform())
    ]
  end

  def nifs(_platform) do
    [
      parser: [
        sources: ["parser.c"],
        pkg_configs: ["libavcodec", "libavutil"],
        preprocessor: Unifex
      ],
      decoder: [
        sources: ["decoder.c"],
        pkg_configs: ["libavcodec", "libavutil"],
        preprocessor: Unifex
      ],
      encoder: [
        sources: ["encoder.c"],
        pkg_configs: ["libavcodec", "libavutil"],
        preprocessor: Unifex
      ]
    ]
  end
end
