#pragma once

#include <erl_nif.h>
#include <libavcodec/avcodec.h>
#include <libavutil/opt.h>
#include <libavutil/imgutils.h>

typedef struct _h264_decoder_state {
  int a;
} State;

#include "_generated/decoder.h"
