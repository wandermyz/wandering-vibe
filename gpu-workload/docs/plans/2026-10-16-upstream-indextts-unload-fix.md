# Plan: send the IndexTTS unload fix upstream

**Status:** in progress. Steps 1–2 done 2026-10-16: fork `wandermyz/TTS-Audio-Suite`,
clone at `~/Codebase/TTS-Audio-Suite` (remotes `origin` = fork, `upstream`),
branch `fix/indextts2-to-device` with the ported `to()` (uncommitted, not pushed).
Unit tests: 153 pass; 1 Fish Audio test fails on plain upstream too. ComfyUI
render tests (step 3) on hold until the GPU is free. No CHANGELOG entry: outside
PRs #368/#369 didn't add one.

Our local patch to [TTS Audio Suite](https://github.com/diodiogod/TTS-Audio-Suite)
fixes IndexTTS-2.5 leaving ~2 GB on the GPU after ComfyUI unloads it. The cause,
the fix and the measurements are in [../tts-audio-suite-vram.md](../tts-audio-suite-vram.md);
the patch is [../../comfyui/tts-audio-suite-indextts-unload.patch](../../comfyui/tts-audio-suite-indextts-unload.patch).
This plan is for offering it to the suite's owner as a pull request, so we can
stop re-applying it after every suite update.

## Why send it

- **Still broken upstream.** On 2026-10-16, `origin/main` (v5.10.3 plus two
  commits, `3f3832a`) still has no `IndexTTS2.to()`.
- **Nobody has reported it.** No issue or PR mentions IndexTTS VRAM or unload.
- **It helps every IndexTTS user,** not only us: ComfyUI's model manager uses the
  same unload when it swaps models inside a session, so a TTS render followed by
  a big model (video) starts ~2 GB short.
- **It matches their own pattern.** Their other engines already define `to()`
  for exactly this reason, e.g. `engines/chatterbox/tts.py` ("Critical for
  ComfyUI model management - ensures all components move together"). IndexTTS2
  is the one that lacks it.
- **The owner takes outside fixes.** Of the last 15 closed PRs, 6 were merged,
  including small bug fixes from outside contributors (#368, #369). Several
  others were closed unmerged, so a merge isn't guaranteed.
- **It's small:** one method, 24 lines, one file. It applied cleanly to
  `origin/main` on 2026-10-16.

## What changes with the ComfyUI restart in gpu-workload

From 2026-10-16 `gpu-workload` restarts an idle ComfyUI before Strata loads
when its RAM stays high (see [../../README.md](../../README.md)). A restart
frees everything, so the patch is **no longer needed for Strata to load**: if
an update drops it, Strata still loads. It is still needed for ComfyUI itself
(TTS then video in one session). That makes this upstream PR a nice-to-have,
not urgent.

## Steps

1. **Fork and branch** under `wandermyz`:
   ```sh
   gh repo fork diodiogod/TTS-Audio-Suite --clone=false
   ```
   Work in a separate clone (e.g. `~/Codebase/forks/TTS-Audio-Suite`), not in
   ComfyUI's `custom_nodes/` copy, so the running install stays as it is.
   Branch from upstream `main`: `fix/indextts2-to-device`.

2. **Port the patch, cleaned up for upstream:**
   - drop the `LOCAL PATCH (gpu-workload)` marker and the link to our docs;
   - give `to()` a docstring in the style of their chatterbox `to()`;
   - keep the behaviour identical: move the six model modules plus the plain
     tensor attributes inside them, `qwen_emo` if loaded, `semantic_mean/std`,
     `emo_matrix`, `spk_matrix`; clear the cached reference-voice conditioning;
     set `self.device`;
   - **leave out** the QwenEmotion placeholder (the empty `model.safetensors`).
     That's our local VRAM saving, not part of the fix.
   - add a `### Fixed` line under an `Unreleased` heading in `CHANGELOG.md`
     only if their recent outside PRs did that; otherwise leave the changelog
     to the owner (they write it at release time).

3. **Test on their latest code, not on our v5.10.2.** With ComfyUI idle:
   - point ComfyUI's `custom_nodes/TTS-Audio-Suite` at the fork branch (or
     update it to upstream `main` and apply the cleaned patch);
   - restart ComfyUI; run an Akine render (the example in
     `~/.pi/agent/skills/voice-akine/SKILL.md`);
   - `POST /free` with `unload_models`, then read ComfyUI's VRAM from
     `gpu-workload status`. Target: about 500 MiB (was 2066 MiB unpatched);
   - render again after the unload, to check reload works (the dropped
     conditioning cache must rebuild);
   - also render once **with** the real QwenEmotion weights in place, since
     upstream users have them: unload must still go to ~500 MiB;
   - run their unit tests: `python tests/run_tests.py unit/ -m unit -v`.

4. **Open the PR** against `diodiogod/TTS-Audio-Suite:main`. Contents:
   - **Title:** `Fix IndexTTS-2 leaving ~2 GB on the GPU after unload`
   - **Problem:** ComfyUI unloads the wrapped engine with `model.to("cpu")`.
     `IndexTTS2` has no `to()`, so the wrapper moves only its `nn.Module`
     attributes; QwenEmotion (1137 MiB), plain tensors inside modules (s2mel
     `causal_mask`/`freqs_cis`, old-style weight_norm weights, ~180 MiB), the
     emotion/speaker matrices and the cached conditioning stay on the GPU.
   - **Fix:** an `IndexTTS2.to()` like the chatterbox engines have.
   - **Measured** (RTX 5070 Ti, after a render, then unload): 2066 MiB before,
     ~500 MiB after, the CUDA context floor being ~270 MiB.
   - **Tested:** the steps above, with the commit tested.
   - Use `gh pr create` from the fork; no Claude attribution in the PR body
     beyond what the repo's own attribution rule asks for at the time.

5. **Afterwards**
   - **Merged and released:** after updating the suite, check that
     `grep -n "    def to(" engines/index_tts/indextts/infer_v2_5.py` finds
     upstream's method; delete our patch file and mark the re-apply steps in
     `tts-audio-suite-vram.md` and `comfyui-updates.md` as only needed for
     older suite versions.
   - **Changes requested:** update the PR; keep our local patch until a
     release has the fix.
   - **Closed without merge:** keep the local patch; note the PR link and the
     reason in `tts-audio-suite-vram.md`.

## Before starting

Get the user's go-ahead for the fork and the PR: both are public, under their
GitHub account.
