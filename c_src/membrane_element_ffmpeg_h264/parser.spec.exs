module Membrane.Element.FFmpeg.H264.Parser

spec create() :: {:ok :: label, state} | {:error :: label, reason :: atom}

spec parse_frames(payload, state) ::
       {:ok :: label, frame_sizes :: [unsigned], consumed :: unsigned}
       | {:error :: label, reason :: atom}
