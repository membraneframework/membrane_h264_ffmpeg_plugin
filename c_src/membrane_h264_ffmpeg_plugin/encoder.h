#pragma once

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wall" 
#pragma GCC diagnostic ignored "-Wextra" 
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
#include <libavutil/log.h>
#include <libavutil/opt.h>
#pragma GCC diagnostic pop

typedef struct H264EncoderState {
  AVCodecContext *codec_ctx;
  unsigned long last_pts;
} State;

#define ENCODER_SEND_FRAME_ERROR -1
#define ENCODER_ENCODE_ERROR -2

#include "_generated/encoder.h"
