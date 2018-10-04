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

#if (LIBAVCODEC_VERSION_MAJOR < 58)
  avcodec_register_all();
#endif
  state->codec = avcodec_find_decoder(AV_CODEC_ID_H264);
  if (!state->codec) {
    res = create_result_error(env, "nocodec");
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

static int get_frames(UnifexEnv * env, AVPacket * pkt, UnifexPayload *** ret_frames, int *max_frames, int * frame_cnt, State * state){
  AVFrame * frame = av_frame_alloc();
  UnifexPayload ** frames = unifex_alloc((*max_frames) * sizeof(*frames));

  int ret = avcodec_send_packet(state->codec_ctx, pkt);
  if (ret < 0) {
    ret = DECODER_SEND_PKT_ERROR;
    goto exit_get_frames;
  }

  ret = avcodec_receive_frame(state->codec_ctx, frame);
  while(ret != AVERROR(EAGAIN) && ret != AVERROR_EOF) {
    if (ret < 0) {
      ret = DECODER_DECODE_ERROR;
      goto exit_get_frames;
    }

    if (*frame_cnt >= (*max_frames)) {
      *max_frames *= 2;
      frames = unifex_realloc(frames, (*max_frames) * sizeof(*frames));
    }

    size_t payload_size = av_image_get_buffer_size(state->codec_ctx->pix_fmt, frame->width, frame->height, 1);
    frames[*frame_cnt] = unifex_payload_alloc(env, UNIFEX_PAYLOAD_SHM, payload_size);
    av_image_copy_to_buffer(
        frames[*frame_cnt]->data,
        payload_size,
        (const uint8_t* const *) frame->data,
        (const int*) frame->linesize,
        state->codec_ctx->pix_fmt,
        frame->width,
        frame->height,
        1
        );
    (*frame_cnt)++;

    ret = avcodec_receive_frame(state->codec_ctx, frame);
  }
  ret = 0;
exit_get_frames:
  *ret_frames = frames;
  av_frame_free(&frame);
  return ret;
}

UNIFEX_TERM decode(UnifexEnv* env, UnifexPayload * payload, State* state) {
  UNIFEX_TERM res_term;
  AVPacket * pkt = NULL;
  int max_frames = 16, frame_cnt = 0;
  UnifexPayload ** out_frames = NULL;

  pkt = av_packet_alloc();
  av_init_packet(pkt);
  pkt->data = payload->data;
  pkt->size = payload->size;


  int ret = 0;
  if (pkt->size > 0) {
    ret = get_frames(env, pkt, &out_frames, &max_frames, &frame_cnt, state);
  }

  switch (ret) {
  case DECODER_SEND_PKT_ERROR:
    res_term = decode_result_error(env, "send_pkt");
    break;
  case DECODER_DECODE_ERROR:
    res_term = decode_result_error(env, "decode");
    break;
  default:
    res_term = decode_result_ok(env, out_frames, frame_cnt);
  }

  for(int i = 0; i < frame_cnt; i++) {
    unifex_payload_release(out_frames[i]);
  }
  if (out_frames != NULL) {
    unifex_free(out_frames);
  }
  av_packet_free(&pkt);
  return res_term;
}

UNIFEX_TERM flush(UnifexEnv* env, State* state) {
  UNIFEX_TERM res_term;
  int max_frames = 8, frame_cnt = 0;
  UnifexPayload ** out_frames = NULL;

  int ret = get_frames(env, NULL, &out_frames, &max_frames, &frame_cnt, state);
  switch (ret) {
  case DECODER_SEND_PKT_ERROR:
    res_term = flush_result_error(env, "send_pkt");
    break;
  case DECODER_DECODE_ERROR:
    res_term = flush_result_error(env, "decode");
    break;
  default:
    res_term = flush_result_ok(env, out_frames, frame_cnt);
  }

  for(int i = 0; i < frame_cnt; i++) {
    unifex_payload_release(out_frames[i]);
  }
  if (out_frames != NULL) {
    unifex_free(out_frames);
  }
  return res_term;
}
