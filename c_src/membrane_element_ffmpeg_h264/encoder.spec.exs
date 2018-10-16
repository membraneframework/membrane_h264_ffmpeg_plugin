module Membrane.Element.FFmpeg.H264.Encoder.Native

spec create(
       width :: int,
       height :: int,
       pix_fmt :: atom,
       preset :: atom,
       framerate_num :: int,
       framerate_denom :: int,
       crf :: int
     ) :: {:ok :: label, state} | {:error :: label, reason :: atom}

spec encode(payload, state) :: {:ok :: label, [payload]} | {:error :: label, reason :: atom}

spec flush(state) :: {:ok :: label, frames :: [payload]} | {:error :: label, reason :: atom}

dirty :cpu, encode: 2
