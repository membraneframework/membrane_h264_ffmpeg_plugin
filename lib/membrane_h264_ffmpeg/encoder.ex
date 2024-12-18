defmodule Membrane.H264.FFmpeg.Encoder do
  @moduledoc """
  Membrane element that encodes raw video frames to H264 format.

  The element expects each frame to be received in a separate buffer, so the parser
  (`Membrane.Element.RawVideo.Parser`) may be required in a pipeline before
  the encoder (e.g. when input is read from `Membrane.File.Source`).

  Additionally, the encoder has to receive proper stream_format with picture format and dimensions
  before any encoding takes place.

  Please check `t:t/0` for available options.
  """
  use Membrane.Filter
  require Membrane.Logger, as: Logger
  alias __MODULE__.Native
  alias Membrane.Buffer
  alias Membrane.H264
  alias Membrane.H264.FFmpeg.Common
  alias Membrane.RawVideo

  def_input_pad :input,
    flow_control: :auto,
    accepted_format: %RawVideo{pixel_format: format, aligned: true} when format in [:I420, :I422]

  def_output_pad :output,
    flow_control: :auto,
    accepted_format: %H264{alignment: :au, stream_structure: :annexb}

  @default_crf 23
  @default_sc_threshold 40

  @type preset() ::
          :ultrafast
          | :superfast
          | :veryfast
          | :faster
          | :fast
          | :medium
          | :slow
          | :slower
          | :veryslow
          | :placebo

  @type tune() ::
          :film
          | :animation
          | :grain
          | :stillimage
          | :fastdecode
          | :zerolatency

  def_options crf: [
                description: """
                Constant rate factor that affects the quality of output stream.
                Value of 0 is lossless compression while 51 (for 8-bit samples)
                or 63 (10-bit) offers the worst quality.
                The range is exponential, so increasing the CRF value +6 results
                in roughly half the bitrate / file size, while -6 leads
                to roughly twice the bitrate.
                """,
                spec: 0..63,
                default: @default_crf
              ],
              preset: [
                description: """
                Collection of predefined options providing certain encoding.
                The slower the preset chosen, the higher compression for the
                same quality can be achieved.
                """,
                spec: preset(),
                default: :medium
              ],
              profile: [
                description: """
                Sets a limit on the features that the encoder will use to the ones supported in a provided H264 profile.
                Said features will have to be supported by the decoder in order to decode the resulting video.
                It may override other, more specific options affecting compression (e.g setting `max_b_frames` to 2
                while profile is set to `:baseline` will have no effect and no B-frames will be present).
                """,
                spec: H264.profile() | nil,
                default: nil
              ],
              tune: [
                description: """
                Optionally tune the encoder settings for a particular type of source or situation.
                See [`x264` encoder's man page](https://manpages.ubuntu.com/manpages/trusty/man1/x264.1.html) for more info.
                Available options are:
                - `:film` - use for high quality movie content; lowers deblocking
                - `:animation` - good for cartoons; uses higher deblocking and more reference frames
                - `:grain` - preserves the grain structure in old, grainy film material
                - `:stillimage` - good for slideshow-like content
                - `:fastdecode` - allows faster decoding by disabling certain filters
                - `:zerolatency` - good for fast encoding and low-latency streaming
                """,
                spec: tune() | nil,
                default: nil
              ],
              use_shm?: [
                spec: boolean(),
                description:
                  "If true, native encoder will use shared memory (via `t:Shmex.t/0`) for storing frames",
                default: false
              ],
              max_b_frames: [
                spec: non_neg_integer() | nil,
                description:
                  "Maximum number of B-frames between non-B-frames. Set to 0 to encode video without b-frames",
                default: nil
              ],
              gop_size: [
                spec: non_neg_integer() | nil,
                description: "Number of frames in a group of pictures.",
                default: nil
              ],
              sc_threshold: [
                spec: non_neg_integer(),
                description: """
                Sets the threshold for scene change detection. This determines how aggressively `x264`
                will try to insert extra I-frames (higher values increase the number of scene changes detected).
                Set to 0 to disable scene change detection (no extra I-frames will be inserted).
                See [this page](https://en.wikibooks.org/wiki/MeGUI/x264_Settings#scenecut) for more info.
                """,
                default: @default_sc_threshold
              ],
              ffmpeg_params: [
                spec: %{String.t() => String.t()},
                description: """
                A map with parameters that are passed to the encoder.

                You can use options from: https://ffmpeg.org/ffmpeg-codecs.html#libx264_002c-libx264rgb
                and https://ffmpeg.org/ffmpeg-codecs.html#Codec-Options
                Options available in the element options (`t:#{inspect(__MODULE__)}.t/0`), like `sc_threshold` or `crf`,
                must be set there and not through `ffmpeg_params`.
                """,
                default: %{}
              ]

  defmodule FFmpegParam do
    @moduledoc false
    @enforce_keys [:key, :value]
    defstruct @enforce_keys
  end

  @impl true
  def handle_init(_ctx, opts) do
    warn_if_ffmpeg_params_overwrite_module_options(opts.ffmpeg_params)

    state =
      opts
      |> Map.put(:encoder_ref, nil)
      |> Map.put(:keyframe_requested?, false)

    {[], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    %{encoder_ref: encoder_ref, use_shm?: use_shm?} = state
    pts = Common.to_h264_time_base_truncated(buffer.pts)

    case Native.encode(
           buffer.payload,
           pts,
           use_shm?,
           state.keyframe_requested?,
           encoder_ref
         ) do
      {:ok, dts_list, pts_list, frames} ->
        bufs = wrap_frames(dts_list, pts_list, frames)

        {bufs, %{state | keyframe_requested?: false}}

      {:error, reason} ->
        raise "Native encoder failed to encode the payload: #{inspect(reason)}"
    end
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    {timebase_num, timebase_den} =
      case stream_format.framerate do
        nil -> {1, 30}
        {0, _framerate_den} -> {1, 30}
        {framerate_num, framerate_den} -> {framerate_den, framerate_num}
        frames_per_second when is_integer(frames_per_second) -> {1, frames_per_second}
      end

    ffmpeg_params =
      Enum.map(state.ffmpeg_params, fn {key, value} -> %FFmpegParam{key: key, value: value} end)

    with buffers <- flush_encoder_if_exists(state),
         {:ok, new_encoder_ref} <-
           Native.create(
             stream_format.width,
             stream_format.height,
             stream_format.pixel_format,
             state.preset,
             state.tune,
             get_ffmpeg_profile(state.profile),
             state.max_b_frames || -1,
             state.gop_size || -1,
             timebase_num,
             timebase_den,
             state.crf,
             state.sc_threshold,
             ffmpeg_params
           ) do
      stream_format = create_new_stream_format(stream_format, state)
      actions = buffers ++ [stream_format: stream_format]
      {actions, %{state | encoder_ref: new_encoder_ref}}
    else
      {:error, reason} -> raise "Failed to create native encoder: #{inspect(reason)}"
    end
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    buffers = flush_encoder_if_exists(state)
    actions = buffers ++ [end_of_stream: :output]
    {actions, state}
  end

  @impl true
  def handle_event(:input, event, _ctx, state) do
    {[event: {:output, event}], state}
  end

  @impl true
  def handle_event(:output, %Membrane.KeyframeRequestEvent{}, _ctx, state) do
    {[], %{state | keyframe_requested?: true}}
  end

  @impl true
  def handle_event(:output, event, _ctx, state) do
    {[event: {:input, event}], state}
  end

  defp flush_encoder_if_exists(%{encoder_ref: nil}), do: []

  defp flush_encoder_if_exists(%{encoder_ref: encoder_ref, use_shm?: use_shm?}) do
    with {:ok, dts_list, pts_list, frames} <- Native.flush(use_shm?, encoder_ref) do
      wrap_frames(dts_list, pts_list, frames)
    else
      {:error, reason} -> raise "Native encoder failed to flush: #{inspect(reason)}"
    end
  end

  defp wrap_frames([], [], []), do: []

  defp wrap_frames(dts_list, pts_list, frames) do
    Enum.zip([dts_list, pts_list, frames])
    |> Enum.map(fn {dts, pts, frame} ->
      %Buffer{
        pts: Common.to_membrane_time_base_truncated(pts),
        dts: Common.to_membrane_time_base_truncated(dts),
        payload: frame
      }
    end)
    |> then(&[buffer: {:output, &1}])
  end

  defp create_new_stream_format(stream_format, state) do
    {:output,
     %H264{
       alignment: :au,
       framerate: stream_format.framerate,
       height: stream_format.height,
       width: stream_format.width,
       profile: state.profile
     }}
  end

  defp get_ffmpeg_profile(profile) do
    case profile do
      :high_10 -> :high10
      :high_10_intra -> :high10
      :high_422 -> :high422
      :high_422_intra -> :high422
      :high_444 -> :high444
      :high_444_intra -> :high444
      other -> other
    end
  end

  defp warn_if_ffmpeg_params_overwrite_module_options(ffmpeg_params) do
    params_to_options_mapping = %{
      "crf" => "crf",
      "preset" => "preset",
      "profile" => "profile",
      "tune" => "tune",
      "max_b_frames" => "max_b_frames",
      "g" => "gop_size",
      "sc_threshold" => "sc_threshold"
    }

    Map.keys(ffmpeg_params)
    |> Enum.filter(fn param_name -> params_to_options_mapping[param_name] != nil end)
    |> Enum.each(fn param_name ->
      Logger.warning(
        "The parameter: `#{param_name}` you provided in the `ffmpeg_params` map overwrites the setting from the modules option: `#{params_to_options_mapping[param_name]}`."
      )
    end)
  end
end
