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

UNIFEX_TERM decode(UnifexEnv* env, UnifexPayload * payload, State* state) {
  UNIFEX_TERM res_term;
  AVPacket * pkt = NULL;
  AVFrame * frame = NULL;
  size_t max_frames = 16, frame_cnt = 0;
  UnifexPayload ** out_frames = unifex_alloc(max_frames * sizeof(*out_frames));

  pkt = av_packet_alloc();
  av_init_packet(pkt);
  pkt->data = payload->data;
  pkt->size = payload->size;

  frame = av_frame_alloc();

  int ret;

  if (pkt->size > 0) {
    ret = avcodec_send_packet(state->codec_ctx, pkt);
    if (ret < 0) {
      res_term = decode_result_error(env, "send_pkt");
      goto exit_decode;
    }

    while(1) {
      ret = avcodec_receive_frame(state->codec_ctx, frame);

      if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
        break;
      }

      if (ret < 0) {
        res_term = decode_result_error(env, "decode");
        goto exit_decode;
      }

      if (frame_cnt >= max_frames) {
        max_frames *= 2;
        out_frames = unifex_realloc(out_frames, max_frames * sizeof(*out_frames));
      }

      size_t payload_size = av_image_get_buffer_size(state->codec_ctx->pix_fmt, frame->width, frame->height, 1);
      out_frames[frame_cnt] = unifex_payload_alloc(env, UNIFEX_PAYLOAD_SHM, payload_size);
      av_image_copy_to_buffer(
          out_frames[frame_cnt]->data,
          payload_size,
          (const uint8_t* const *) frame->data,
          (const int*) frame->linesize,
          state->codec_ctx->pix_fmt,
          frame->width,
          frame->height,
          1
          );
      frame_cnt++;
    }
  }

  res_term = decode_result_ok(env, out_frames, frame_cnt);
exit_decode:
  for(size_t i = 0; i < frame_cnt; i++) {
    unifex_payload_release(out_frames[i]);
  }
  av_frame_free(&frame);
  av_packet_free(&pkt);
  return res_term;
}

UNIFEX_TERM flush(UnifexEnv* env, State* state) {
  int ret;
  UNIFEX_TERM res_term;
  AVFrame * frame = NULL;
  size_t max_frames = 8, frame_cnt = 0;
  UnifexPayload ** out_frames = unifex_alloc(max_frames * sizeof(*out_frames));

  frame = av_frame_alloc();

  ret = avcodec_send_packet(state->codec_ctx, NULL);
  if (ret < 0) {
    res_term = flush_result_error(env, "send_pkt");
    goto exit_flush;
  }

  while(1) {
    ret = avcodec_receive_frame(state->codec_ctx, frame);

    if (ret == AVERROR_EOF) {
      break;
    }

    if (ret < 0) {
      res_term = flush_result_error(env, "decode");
      goto exit_flush;
    }

    if (frame_cnt >= max_frames) {
      max_frames *= 2;
      out_frames = unifex_realloc(out_frames, max_frames * sizeof(*out_frames));
    }

    size_t payload_size = av_image_get_buffer_size(state->codec_ctx->pix_fmt, frame->width, frame->height, 1);
    out_frames[frame_cnt] = unifex_payload_alloc(env, UNIFEX_PAYLOAD_SHM, payload_size);
    av_image_copy_to_buffer(
        out_frames[frame_cnt]->data,
        payload_size,
        (const uint8_t* const *) frame->data,
        (const int*) frame->linesize,
        state->codec_ctx->pix_fmt,
        frame->width,
        frame->height,
        1
        );
    frame_cnt++;
  }

  res_term = flush_result_ok(env, out_frames, frame_cnt);
exit_flush:
  for(size_t i = 0; i < frame_cnt; i++) {
    unifex_payload_release(out_frames[i]);
  }
  av_frame_free(&frame);
  return res_term;
}
