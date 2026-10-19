#include "llama.h"
#include <algorithm>
#include <cstring>
#include <string>
#include <vector>
#include <cmath>

#if defined(_WIN32)
#define CUE_EXPORT __declspec(dllexport)
#else
#define CUE_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

struct CueModel { llama_model *model; };
extern "C" {
CUE_EXPORT void *cue_load(const char *path) {
  llama_backend_init();
  auto params = llama_model_default_params();
  params.n_gpu_layers = 0;
  auto *model = llama_model_load_from_file(path, params);
  return model ? new CueModel{model} : nullptr;
}
CUE_EXPORT void cue_free(void *handle) {
  if (!handle) return;
  auto *state = static_cast<CueModel *>(handle);
  llama_model_free(state->model);
  delete state;
}
CUE_EXPORT int cue_embed(void *handle, const char *text, float *output, int capacity) {
  if (!handle || !text || !output) return -1;
  auto *state = static_cast<CueModel *>(handle);
  const auto *vocab = llama_model_get_vocab(state->model);
  const int dims = llama_model_n_embd(state->model);
  if (dims > capacity) return -2;
  auto params = llama_context_default_params();
  params.n_ctx = 2048; params.n_batch = 2048; params.n_ubatch = 2048;
  params.n_threads = 2; params.n_threads_batch = 2;
  params.embeddings = true; params.pooling_type = LLAMA_POOLING_TYPE_MEAN;
  auto *ctx = llama_init_from_model(state->model, params);
  if (!ctx) return -3;
  int count = -llama_tokenize(vocab, text, static_cast<int>(std::strlen(text)), nullptr, 0, true, true);
  if (count <= 0 || count > 2048) { llama_free(ctx); return -4; }
  std::vector<llama_token> tokens(count);
  llama_tokenize(vocab, text, static_cast<int>(std::strlen(text)), tokens.data(), count, true, true);
  auto batch = llama_batch_get_one(tokens.data(), count);
  const int status = llama_model_has_encoder(state->model) ? llama_encode(ctx, batch) : llama_decode(ctx, batch);
  const float *embedding = status == 0 ? llama_get_embeddings_seq(ctx, 0) : nullptr;
  if (!embedding) { llama_free(ctx); return -5; }
  double norm = 0;
  for (int i = 0; i < dims; ++i) norm += embedding[i] * embedding[i];
  norm = std::sqrt(norm);
  if (norm == 0) { llama_free(ctx); return -6; }
  for (int i = 0; i < dims; ++i) output[i] = static_cast<float>(embedding[i] / norm);
  llama_free(ctx);
  return dims;
}
// Output is bounded and owned by Dart. Context is fresh per decision.
CUE_EXPORT int cue_complete(void *handle, const char *prompt, char *output, int capacity) {
  if (!handle || capacity < 2) return -1;
  auto *state = static_cast<CueModel *>(handle);
  const auto *vocab = llama_model_get_vocab(state->model);
  auto params = llama_context_default_params();
  params.n_ctx = 2048; params.n_batch = 2048;
  params.n_threads = 2; params.n_threads_batch = 2;
  auto *ctx = llama_init_from_model(state->model, params);
  if (!ctx) return -2;
  int count = -llama_tokenize(vocab, prompt, static_cast<int>(std::strlen(prompt)), nullptr, 0, true, true);
  if (count <= 0 || count > 1750) { llama_free(ctx); return -3; }
  std::vector<llama_token> tokens(count);
  llama_tokenize(vocab, prompt, static_cast<int>(std::strlen(prompt)), tokens.data(), count, true, true);
  auto *sampler = llama_sampler_init_greedy();
  std::string text;
  auto batch = llama_batch_get_one(tokens.data(), count);
  int status = 0;
  for (int i = 0; i < 180; ++i) {
    if (llama_decode(ctx, batch) != 0) { status = -4; break; }
    const auto token = llama_sampler_sample(sampler, ctx, -1);
    if (llama_vocab_is_eog(vocab, token)) break;
    char piece[512];
    const int size = llama_token_to_piece(vocab, token, piece, sizeof(piece), 0, true);
    if (size > 0) text.append(piece, size);
    if (text.size() >= static_cast<size_t>(capacity - 1)) break;
    tokens.assign(1, token);
    batch = llama_batch_get_one(tokens.data(), 1);
  }
  llama_sampler_free(sampler); llama_free(ctx);
  if (status < 0) return status;
  const int length = std::min(static_cast<int>(text.size()), capacity - 1);
  std::memcpy(output, text.data(), length); output[length] = 0;
  return length;
}
}
