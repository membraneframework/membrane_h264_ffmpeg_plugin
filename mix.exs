defmodule Membrane.H264.FFmpeg.Plugin.MixProject do
  use Mix.Project

  @version "0.18.0"
  @github_url "https://github.com/membraneframework/membrane_h264_ffmpeg_plugin"

  def project do
    [
      app: :membrane_h264_ffmpeg_plugin,
      compilers: [:unifex, :bundlex] ++ Mix.compilers(),
      version: @version,
      elixir: "~> 1.12",
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
      formatters: ["html"],
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [
        Membrane.H264.FFmpeg
      ]
    ]
  end

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @github_url,
        "Membrane Framework Homepage" => "https://membraneframework.org"
      },
      files: ["lib", "mix.exs", "README*", "LICENSE*", ".formatter.exs", "bundlex.exs", "c_src"]
    ]
  end

  defp deps do
    [
      {:bunch, "~> 1.3.0"},
      {:unifex, "~> 0.7.2"},
      {:membrane_core, "~> 0.9.0"},
      {:membrane_common_c, "~> 0.11.0"},
      {:membrane_h264_format, "~> 0.3.0"},
      {:membrane_raw_video_format, "~> 0.2.0"},
      {:ratio, "~> 2.4.0"},
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:credo, "~> 1.6", only: :dev, runtime: false},
      {:dialyxir, "~> 1.1", only: :dev, runtime: false},
      {:membrane_raw_video_parser_plugin, "~> 0.7", only: :test},
      {:membrane_file_plugin, "~> 0.8", only: :test}
    ]
  end
end
