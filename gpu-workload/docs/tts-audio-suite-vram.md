# TTS Audio Suite: IndexTTS kept VRAM after unload

ComfyUI has the [TTS Audio Suite](https://github.com/diodiogod/TTS-Audio-Suite)
custom node pack installed for the Akine (秋音) voice, which uses
IndexTTS-2.5. Up to version 5.10.3, IndexTTS didn't fully leave the GPU when
ComfyUI unloaded it, and we patched the suite locally.

**Fixed upstream (2026-10-17):** our fix was merged as
[PR #373](https://github.com/diodiogod/TTS-Audio-Suite/pull/373) and released in
**5.10.4**, which is installed here. The local patch is gone. What follows is
the record of the problem; only "QwenEmotion weights set aside" still applies.

## The problem

After an IndexTTS render, `POST /free` reported "freed 4804MB", but ComfyUI
still held about 2 GB:

```
gpu:    … (strata 0, comfy 2066, other 0)
last:   … strata-load (allowed=False, reason=could not free ComfyUI's 2066 MiB:
        timed out after 20s waiting for ComfyUI to release VRAM (below 1500 MiB) …)
```

That's above `COMFY_IDLE_MIB` (1500), so every Strata load was refused until
ComfyUI restarted. Nothing in gpu-workload was wrong: ComfyUI simply never got
below the threshold.

## Cause

The suite wraps the IndexTTS2 engine object (`engines/index_tts/indextts/infer_v2_5.py`)
for ComfyUI's model manager. On unload, the wrapper calls `model.to("cpu")` if
the object has a `to()`, and otherwise moves each `nn.Module` attribute one
by one. `IndexTTS2` has no `to()`, so only the modules moved. Left on the GPU
(measured standalone, render under `torch.inference_mode()` as ComfyUI does):

| Left behind | Size |
| --- | --- |
| `qwen_emo` (QwenEmotion, a Qwen 0.6B text-to-emotion model; not an `nn.Module` attribute, so never moved) | 1137 MiB |
| Plain tensor attributes inside modules, which `Module.to()` skips: old-style `weight_norm` weights in `s2mel`, `s2mel` `causal_mask` (64 MiB) and `freqs_cis` | ~180 MiB |
| Cached reference-voice conditioning, emotion/speaker matrices | ~8 MiB |
| Allocator cache held because of the above | the rest |

QwenEmotion loads whenever `IndexTTS-2.5/qwen0.6bemo4-merge/` exists, even
though Akine renders use the emotion sliders and never call it.

## The fix

### 1. Patch: add `IndexTTS2.to()`

[`../comfyui/tts-audio-suite-indextts-unload.patch`](../comfyui/tts-audio-suite-indextts-unload.patch)
adds a `to(device)` method to `IndexTTS2` in `infer_v2_5.py`. The wrapper uses
it for both unload and reload. It:

- moves every model module, plus the plain tensor attributes inside them;
- moves QwenEmotion if it's loaded;
- moves the emotion/speaker matrices and the semantic mean/std;
- drops the cached reference-voice conditioning (it's rebuilt on the next
  render).

The patch is marked `LOCAL PATCH (gpu-workload)` in the source. It was made
against suite commit `49538a4` (v5.10.2).

### 2. QwenEmotion weights set aside

This saves 1.1 GiB of VRAM during every render. Simply moving the folder away
doesn't work: the suite's downloader lists its files as required and silently
downloads them again on the next render. Instead:

- The real weights are in `ComfyUI/models/TTS/IndexTTS-disabled/qwen0.6bemo4-merge/`.
- `IndexTTS-2.5/qwen0.6bemo4-merge/model.safetensors` is an **empty file**, so
  the downloader sees a complete model. QwenEmotion then fails to load, which
  the suite handles gracefully. The log shows:
  `QwenEmotion failed to load (… header too small); text emotion disabled`.
- `DISABLED.txt` in that folder explains this.

The only thing lost is the **🌈 IndexTTS-2 Text Emotion** node. Emotion vectors
and emotion audio still work. To bring the node back, copy the weights over the
placeholder:

```sh
cd ~/Codebase/ComfyUI/models/TTS
cp IndexTTS-disabled/qwen0.6bemo4-merge/model.safetensors IndexTTS/IndexTTS-2.5/qwen0.6bemo4-merge/
```

With the patch, unload stays clean even with QwenEmotion loaded, so this is a
VRAM saving, not part of the fix.

## Result

| After an Akine render and unload | ComfyUI VRAM |
| --- | --- |
| Unpatched, as installed | 2066 MiB: Strata refused |
| Qwen weights aside, no patch | ~760 MiB |
| **Patched** (with or without Qwen) | **~340 MiB** standalone, 498 MiB in ComfyUI |
| Floor: any process that has used CUDA | ~270 MiB |

ComfyUI never goes to 0 MiB once it has used the GPU: the CUDA context stays
until the process exits.

Verified on 2026-10-13: Akine render (ComfyUI at 5554 MiB), then
`gpu-workload switch strata` succeeded with ComfyUI at 498 MiB.

## Since gpu-workload restarts a heavy ComfyUI (2026-10-16)

Before Strata loads, gpu-workload now restarts an idle ComfyUI whose VRAM
won't drop below 1500 MiB after `/free`, or that holds more than 4 GiB of
RAM + swap (see the README). A restart frees everything, so the patch is **no
longer needed for Strata to load**: without it ComfyUI stays at ~2 GB VRAM,
and gpu-workload restarts it (~20 s more for that handover) instead of
refusing Strata. The patch still matters inside
ComfyUI: its model manager uses the same unload when it swaps models, so a TTS
render followed by a video in one session starts ~2 GB short. Keep re-applying
it; it just isn't urgent any more. Sending it upstream is planned in
[plans/2026-10-16-upstream-indextts-unload-fix.md](plans/2026-10-16-upstream-indextts-unload-fix.md).

## After a TTS Audio Suite update

Since 5.10.4 there's no patch to re-apply. If an update ever brings the leak
back, the symptom is the event log showing `restarted it: kept ~2000 MiB of
VRAM after /free` after TTS renders; the fix was an `IndexTTS2.to()` that moves
every part of the engine (see "The fix" above).

**Check the Qwen placeholder survived.** An update to the downloader, or a
   new IndexTTS revision, can make it fetch the weights again:
   ```sh
   ls -la ~/Codebase/ComfyUI/models/TTS/IndexTTS/IndexTTS-2.5/qwen0.6bemo4-merge/model.safetensors
   ```
   It should be 0 bytes. If it's ~1.1 GB again, truncate it: `: > …/model.safetensors`.

The same problem can affect **other engines** in the suite. Each engine's
wrapped object needs a `to()` that moves everything. If a different engine
leaves ComfyUI above 1500 MiB after `/free`, find what's left over the same
way: in a standalone script, render, call the suite's unload, then list
`gc.get_objects()` tensors that are still `is_cuda`.
