#include "parser.h"

void handle_destroy_state(UnifexEnv * env, State * state) {
  UNIFEX_UNUSED(env);

  if (state->parser_ctx != NULL) {
    av_parser_close(state->parser_ctx);
  }

  if (state->codec_ctx != NULL) {
    avcodec_free_context(&state->codec_ctx);
  }
}

UNIFEX_TERM create(UnifexEnv *env) {
  UNIFEX_TERM res;
  State * state = unifex_alloc_state(env);
  state->codec = NULL;
  state->codec_ctx = NULL;
  state->parser_ctx = NULL;

  state->codec = avcodec_find_decoder(AV_CODEC_ID_H264);
  if (!state->codec) {
    res = create_result_error(env, "nocodec");
    goto exit_create;
  }

  state->parser_ctx = av_parser_init(state->codec->id);
  if (!state->parser_ctx) {
    res = create_result_error(env, "noparser");
    goto exit_create;
  }

  state->codec_ctx = avcodec_alloc_context3(state->codec);
  if (!state->codec_ctx) {
    res = create_result_error(env, "codec_alloc");
    goto exit_create;
  }

  if(avcodec_open2(state->codec_ctx, state->codec, NULL) < 0) {
    res = create_result_error(env, "codec_open");
    goto exit_create;
  }

  res = create_result_ok(env, state);
exit_create:
  unifex_release_state(env, state);
  return res;
}

UNIFEX_TERM parse_frames(UnifexEnv* env, UnifexPayload * payload, State* state) {
  UNIFEX_TERM res_term;
  size_t max_frames = 32, frames_cnt = 0;
  unsigned * out_frame_sizes = unifex_alloc(max_frames * sizeof(unsigned));

  AVPacket * pkt = NULL;
  size_t old_size = payload->size;
  unifex_payload_realloc(payload, old_size + AV_INPUT_BUFFER_PADDING_SIZE);
  memset(payload->data + old_size, 0, AV_INPUT_BUFFER_PADDING_SIZE);

  pkt = av_packet_alloc();
  av_init_packet(pkt);

  int ret;

  uint8_t * data_ptr = payload->data;
  size_t data_left = old_size;

  while (data_left > 0) {
    ret = av_parser_parse2(state->parser_ctx, state->codec_ctx, &pkt->data, &pkt->size,
                           data_ptr, data_left, AV_NOPTS_VALUE, AV_NOPTS_VALUE, 0);
    if (ret < 0) {
      res_term = parse_frames_result_error(env, "parsing");
      goto exit_parse_frames;
    }
    if (ret == 0) {
      break;
    }

    data_ptr += ret;
    data_left -= ret;

    if (frames_cnt >= max_frames) {
      max_frames *= 2;
      out_frame_sizes = unifex_realloc(out_frame_sizes, max_frames * sizeof(unsigned));
    }

    out_frame_sizes[frames_cnt] = pkt->size;
    frames_cnt++;
  }

  res_term = parse_frames_result_ok(env, out_frame_sizes, frames_cnt, old_size - data_left);
exit_parse_frames:
  unifex_free(out_frame_sizes);
  av_packet_free(&pkt);
  unifex_payload_realloc(payload, old_size);
  return res_term;
}
