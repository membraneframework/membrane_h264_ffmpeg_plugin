#pragma once

#include <erl_nif.h>
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>

typedef struct _h264_decoder_state {
  AVCodec *codec;
  AVCodecContext *codec_ctx;
  AVCodecParserContext *parser_ctx;
} UnifexNifState;

typedef UnifexNifState State;

#include "_generated/decoder.h"

#define DECODER_SEND_PKT_ERROR -1
#define DECODER_DECODE_ERROR -2
