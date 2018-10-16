#pragma once

#include <libavcodec/avcodec.h>
#include <libavutil/opt.h>
#include <libavutil/imgutils.h>

typedef struct H264EncoderState {
  AVCodecContext *codec_ctx;
  unsigned long last_pts;
} UnifexNifState;

typedef UnifexNifState State;

#define ENCODER_SEND_FRAME_ERROR -1
#define ENCODER_ENCODE_ERROR -2

#include "_generated/encoder.h"
