defmodule Membrane.Element.FFmpeg.H264.MixProject do
  use Mix.Project

  @version "0.1.0"
  @github_url "https://github.com/membraneframework/membrane-element-ffmpeg-h264"

  def project do
    [
      app: :membrane_element_ffmpeg_h264,
      compilers: [:unifex, :bundlex] ++ Mix.compilers(),
      version: @version,
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      description: "Membrane Multimedia Framework (FFmpeg H264 Element)",
      package: package(),
      name: "Membrane Element: H264",
      source_url: @github_url,
      docs: docs(),
      homepage_url: "https://membraneframework.org",
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: []
    ]
  end

  def docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}"
    ]
  end

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache 2.0"],
      links: %{
        "GitHub" => @github_url,
        "Membrane Framework Homepage" => "https://membraneframework.org"
      },
      files: ["lib", "mix.exs", "README*", "LICENSE*", ".formatter.exs", "bundlex.exs", "c_src"]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.19.0", only: :dev, runtime: false},
      {:membrane_core, github: "membraneframework/membrane-core", override: true},
      {:bundlex, "~> 0.1.3"},
      {:unifex, "~> 0.1.0", github: "membraneframework/unifex", branch: "misc-ffmpeg-h264"},
      {:bunch, github: "membraneframework/bunch", override: true},
      {:membrane_element_file, path: "../../file", only: :test}
    ]
  end
end
