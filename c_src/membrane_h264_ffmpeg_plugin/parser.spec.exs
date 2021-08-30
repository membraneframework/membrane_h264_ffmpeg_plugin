module Membrane.H264.FFmpeg.Parser.Native

state_type "State"

spec create() :: {:ok :: label, state} | {:error :: label, reason :: atom}

spec parse(payload, state) ::
       {:ok :: label, frame_sizes :: [unsigned], change_idx :: int}
       | {:error :: label, reason :: atom}

spec get_parsed_meta(state) :: {:ok :: label, width :: int, height :: int, profile :: atom}

spec flush(state) ::
       {:ok :: label, frame_sizes :: [unsigned]}
       | {:error :: label, reason :: atom}
