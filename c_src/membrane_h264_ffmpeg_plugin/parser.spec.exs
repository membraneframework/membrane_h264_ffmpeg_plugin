module Membrane.H264.FFmpeg.Parser.Native

state_type "State"

type(
  resolution :: %Resolution{
    width: int,
    height: int,
    index: int
  }
)

spec create() :: {:ok :: label, state} | {:error :: label, reason :: atom}

spec parse(payload, state) ::
       {:ok :: label, frame_sizes :: [unsigned], resolutions :: [resolution]}
       | {:error :: label, reason :: atom}

spec get_profile(state) :: {:ok :: label, profile :: atom}

spec flush(state) ::
       {:ok :: label, frame_sizes :: [unsigned]}
       | {:error :: label, reason :: atom}
