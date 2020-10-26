defmodule Membrane.H264.FFmpeg.Plugin.MixProject do
  use Mix.Project

  @version "0.5.0"
  @github_url "https://github.com/membraneframework/membrane_h264_ffmpeg_plugin"

  def project do
    [
      app: :membrane_h264_ffmpeg_plugin,
      compilers: [:unifex, :bundlex] ++ Mix.compilers(),
      version: @version,
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: "Membrane H264 parser, decoder and encoder based on FFmpeg and x264",
      package: package(),
      name: "Membrane H264 FFmpeg plugin",
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
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [
        Membrane.H264.FFmpeg
      ]
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
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:membrane_core, "~> 0.5.0"},
      {:membrane_common_c, "~> 0.4.0"},
      {:membrane_caps_video_h264, "~> 0.2.0"},
      {:membrane_caps_video_raw, "~> 0.1.0"},
      {:unifex, "~> 0.3.0"},
      {:bunch, "~> 1.2"},
      {:membrane_element_rawvideo_parser, "~> 0.2.0", only: [:dev, :test]},
      {:membrane_element_file, "~> 0.3.0", only: [:dev, :test]},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end
end
