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
        deps: [unifex: :unifex],
        sources: ["_generated/parser.c", "parser.c"],
        pkg_configs: ["libavcodec", "libavutil"]
      ],
      decoder: [
        deps: [unifex: :unifex],
        sources: ["_generated/decoder.c", "decoder.c"],
        pkg_configs: ["libavcodec", "libavutil"]
      ],
      encoder: [
        deps: [unifex: :unifex],
        sources: ["_generated/encoder.c", "encoder.c"],
        pkg_configs: ["libavcodec", "libavutil"]
      ]
    ]
  end
end
