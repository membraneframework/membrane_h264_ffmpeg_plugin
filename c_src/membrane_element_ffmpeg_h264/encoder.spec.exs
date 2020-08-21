module Membrane.Element.FFmpeg.H264.Encoder.Native

state_type "State"

spec create(
       width :: int,
       height :: int,
       pix_fmt :: atom,
       preset :: atom,
       profile :: atom,
       framerate_num :: int,
       framerate_denom :: int,
       crf :: int
     ) :: {:ok :: label, state} | {:error :: label, reason :: atom}

spec get_frame_size(state) :: {:ok :: label, frame_size :: int} | {:error :: label}

spec encode(payload, state) :: {:ok :: label, [payload]} | {:error :: label, reason :: atom}

spec flush(state) :: {:ok :: label, frames :: [payload]} | {:error :: label, reason :: atom}

dirty :cpu, encode: 2, flush: 1
