#include "decoder.h"

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
  state->codec_ctx->width = 1280;
  state->codec_ctx->height = 720;
  state->codec_ctx->pix_fmt = AV_PIX_FMT_YUV420P;

  if(avcodec_open2(state->codec_ctx, state->codec, NULL) < 0) {
    res = create_result_error(env, "codec_open");
    goto exit_create;
  }

  res = create_result_ok(env, state);
exit_create:
  unifex_release_state(env, state);
  return res;
}

int get_frames(UnifexEnv * env, AVFrame * frame, UnifexPayloadType payload_type, UnifexPayload * out_payloads[], State* state) {
  int ret = 0;
  int payload_cnt = 0;
  while(1) {
    ret = avcodec_receive_frame(state->codec_ctx, frame);

    if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
      return payload_cnt;
    }

    if (ret < 0) {
      return ret;
    }

    size_t payload_size = av_image_get_buffer_size(state->codec_ctx->pix_fmt, frame->width, frame->height, 16);
    out_payloads[payload_cnt] = unifex_payload_alloc(env, payload_type, payload_size);
    av_image_copy_to_buffer(
        out_payloads[payload_cnt]->data,
        payload_size,
        (const uint8_t* const *) frame->data,
        (const int*) frame->linesize,
        state->codec_ctx->pix_fmt,
        frame->width,
        frame->height,
        16
        );
    payload_cnt++;
  }
}

UNIFEX_TERM decode_frame(UnifexEnv* env, UnifexPayload * payload, State* state) {
  UNIFEX_TERM res_term;
  AVPacket * pkt = NULL;
  AVFrame * frame = NULL;
  size_t old_size = payload->size;
  static const size_t MAX_PAYLOADS = 100;
  UnifexPayload * out_payloads[MAX_PAYLOADS];
  size_t payload_cnt = 0;
  unifex_payload_realloc(payload, old_size + AV_INPUT_BUFFER_PADDING_SIZE);
  memset(payload->data + old_size, 0, AV_INPUT_BUFFER_PADDING_SIZE);

  pkt = av_packet_alloc();
  av_init_packet(pkt);
  frame = av_frame_alloc();

  int ret;

  uint8_t * data_ptr = payload->data;
  size_t data_left = old_size;

  while (data_left > 0) {
    ret = av_parser_parse2(state->parser_ctx, state->codec_ctx, &pkt->data, &pkt->size,
                           data_ptr, data_left, AV_NOPTS_VALUE, AV_NOPTS_VALUE, 0);
    if (ret < 0) {
      res_term = decode_frame_result_error(env, "parsing");
      goto exit_decode;
    }
    if (ret == 0) {
      res_term = decode_frame_result_error(env, "buflen");
      goto exit_decode;
    }

    data_ptr += ret;
    data_left -= ret;

    if (pkt->size > 0) {
      ret = avcodec_send_packet(state->codec_ctx, pkt);
      if (ret < 0) {
        res_term = decode_frame_result_error(env, "send_pkt");
        goto exit_decode;
      }

      ret = get_frames(env, frame, payload->type, out_payloads + payload_cnt, state);
      if (ret < 0) {
        res_term = decode_frame_result_error(env, "decode");
        goto exit_decode;
      }
      payload_cnt += ret;
    }
  }

  res_term = decode_frame_result_ok(env, out_payloads, payload_cnt);
exit_decode:
  for(size_t i = 0; i < payload_cnt; i++) {
    unifex_payload_release(out_payloads[i]);
  }
  av_frame_free(&frame);
  av_packet_free(&pkt);
  return res_term;
}
