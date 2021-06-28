module Membrane.H264.FFmpeg.Encoder.Native

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

spec encode(payload, state) ::
       {:ok :: label, dts_list :: [int64], [payload]} | {:error :: label, reason :: atom}

spec encode_with_pts(payload, pts :: int64, state) ::
       {:ok :: label, dts_list :: [int64], [payload]} | {:error :: label, reason :: atom}

spec flush(state) ::
       {:ok :: label, dts_list :: [int64], frames :: [payload]}
       | {:error :: label, reason :: atom}

dirty :cpu, encode: 2, flush: 1, encode_with_pts: 3
