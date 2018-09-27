module Membrane.Element.FFmpeg.H264.Decoder

spec create() :: {:ok :: label, state} | {:error :: label, reason :: atom}

spec decode(payload, state) :: {:ok :: label, [payload]} | {:error :: label, reason :: atom}

spec flush(state) :: {:ok :: label, frames :: [payload]} | {:error :: label, reason :: atom}
