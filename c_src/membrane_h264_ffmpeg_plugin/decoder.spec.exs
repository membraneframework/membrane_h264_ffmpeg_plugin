module Membrane.H264.FFmpeg.Decoder.Native

state_type "State"

spec create() :: {:ok :: label, state} | {:error :: label, reason :: atom}

spec decode(payload, state) :: {:ok :: label, [payload]} | {:error :: label, reason :: atom}

spec flush(state) :: {:ok :: label, frames :: [payload]} | {:error :: label, reason :: atom}

spec get_metadata(state) ::
       {:ok :: label, width :: int, height :: int, pix_fmt :: atom}
       | {:error :: label, :pix_fmt :: label}

dirty :cpu, decode: 2, flush: 1
