module Membrane.Element.FFmpeg.H264.Parser.Native

spec create() :: {:ok :: label, state} | {:error :: label, reason :: atom}

spec parse(payload, state) ::
       {:ok :: label, frame_sizes :: [unsigned]}
       | {:error :: label, reason :: atom}

spec get_parsed_meta(state) :: {:ok :: label, width :: int, height :: int, profile :: atom}

spec flush(state) ::
       {:ok :: label, frame_sizes :: [unsigned]}
       | {:error :: label, reason :: atom}
