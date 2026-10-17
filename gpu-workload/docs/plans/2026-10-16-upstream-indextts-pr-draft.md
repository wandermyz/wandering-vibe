# PR draft: diodiogod/TTS-Audio-Suite

- **From:** `wandermyz:fix/indextts2-to-device` (commit `3539778b`)
- **To:** `diodiogod/TTS-Audio-Suite:main`
- **Title:** Fix IndexTTS-2 leaving ~2 GB on the GPU after unload

---

## The problem

After an IndexTTS-2 render, unloading the model (ComfyUI's "Unload models", or `POST /free` with `unload_models`) leaves about 2 GB on the GPU. ComfyUI reports the memory as freed, but `nvidia-smi` still shows it held by the ComfyUI process. That memory is missing for whatever runs next in the same session, for example a video model after a TTS line.

## The cause

ComfyUI unloads the wrapped engine with `model.to("cpu")`. `IndexTTS2` has no `to()`, so the wrapper falls back to moving each `nn.Module` attribute one by one. Everything else stays on the GPU:

| Left on the GPU | Size |
| --- | --- |
| `qwen_emo` (QwenEmotion): not an `nn.Module` attribute, so never moved | ~1.1 GB |
| Plain tensor attributes inside modules, which `Module.to()` skips: `s2mel` `causal_mask` and `freqs_cis`, old-style `weight_norm` weights | ~180 MB |
| `emo_matrix` / `spk_matrix`, `semantic_mean` / `semantic_std`, cached reference-voice conditioning | ~8 MB |

The allocator cache that these pin accounts for the rest.

## The change

Add `IndexTTS2.to(device)` in `engines/index_tts/indextts/infer_v2_5.py`, like the chatterbox engines already have. It:

- moves the six model modules (`gpt`, `semantic_model`, `semantic_codec`, `s2mel`, `campplus_model`, `bigvgan`), plus the plain tensor attributes inside them;
- moves `qwen_emo` if it's loaded;
- moves `semantic_mean` / `semantic_std` and the emotion/speaker matrices;
- clears the cached reference-voice conditioning, which is rebuilt on the next render;
- sets `self.device`.

One file, 29 lines, no behaviour change while the model is loaded.

## Testing

On `main` at `3f3832a`, in ComfyUI, RTX 5070 Ti (16 GB). Each run is a Japanese IndexTTS-2.5 render with emotion vectors and a reference voice, then `POST /free` with `unload_models`. The VRAM figures are the ComfyUI process's usage from `nvidia-smi`:

| Run | Peak | After unload |
| --- | --- | --- |
| `main`, unpatched | 6706 MiB | **2066 MiB** |
| This PR | 6706 MiB | **466 MiB** |
| This PR, render again after the unload (new text) | 5586 MiB* | 498 MiB |

\* The model was reloaded without QwenEmotion for this run.

The render after an unload works: the model moves back to CUDA and the conditioning is rebuilt. About 270 MiB of what's left is the CUDA context, which stays until the process exits.

Unit tests (`python tests/run_tests.py unit/ -m unit`): 153 passed. One test fails the same way on `main` without this change: `test_fish_audio_s2_processor.py::test_custom_override_logs_connected_voice_and_does_not_inherit_alias_language`. It needs `folder_paths.get_system_user_directory`, which my ComfyUI build doesn't have.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
