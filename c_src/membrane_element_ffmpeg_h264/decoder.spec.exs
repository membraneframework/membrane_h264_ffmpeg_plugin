module Membrane.Element.FFmpeg.H264.Decoder

spec create() :: {:ok :: label, state}

spec decode_frame(payload, state) :: {:ok :: label, payload} | {:error :: label, reason :: atom}
