#include "decoder.h"

UNIFEX_TERM create(UnifexEnv *env) {
  State * state = unifex_alloc_state(env);

  state->a = 42;

  return create_result_ok(env, state);
}
