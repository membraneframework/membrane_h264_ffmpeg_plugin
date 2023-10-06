#pragma once

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wall" 
#pragma GCC diagnostic ignored "-Wextra" 
#include <erl_nif.h>
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#pragma GCC diagnostic pop

typedef struct _h264_parser_state {
  AVCodecContext *codec_ctx;
  AVCodecParserContext *parser_ctx;
  int last_frame_number;
  // picture order counter offset
  int poc_offset;
} 
State;

#include "_generated/parser.h"
