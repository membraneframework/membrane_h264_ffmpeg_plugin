defmodule Membrane.Element.FFmpeg.H264.MixProject do
  use Mix.Project

  @version "0.1.1"
  @github_url "https://github.com/membraneframework/membrane-element-ffmpeg-h264"

  def project do
    [
      app: :membrane_element_ffmpeg_h264,
      compilers: [:unifex, :bundlex] ++ Mix.compilers(),
      version: @version,
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
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

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp docs do
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
      {:membrane_core, "~> 0.2.2"},
      {:membrane_common_c, "~> 0.2"},
      {:membrane_caps_video_h264, "~> 0.1"},
      {:membrane_caps_video_raw, "~> 0.1"},
      {:bundlex, "~> 0.1.8"},
      {:unifex, "~> 0.2.0"},
      {:bunch, "~> 1.0"},
      {:membrane_element_rawvideo_parser, "~> 0.1", only: [:dev, :test]},
      {:membrane_element_file, "~> 0.2", only: [:dev, :test]}
    ]
  end
end
