defmodule Membrane.Element.FFmpeg.H264.BundlexProject do
  use Bundlex.Project

  def project() do
    [
      nifs: nifs(Bundlex.platform())
    ]
  end

  def nifs(_platform) do
    [
      decoder: [
        deps: [unifex: :unifex],
        sources: ["_generated/decoder.c", "decoder.c"],
        pkg_configs: ["libavcodec", "libavutil"]
      ]
    ]
  end
end
