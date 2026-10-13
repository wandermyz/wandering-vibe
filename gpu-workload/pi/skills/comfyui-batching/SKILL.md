---
name: comfyui-batching
description: Use whenever you queue ComfyUI jobs (POST to 127.0.0.1:8188/prompt, or a script that does) on this machine. The GPU is shared with the LLM you run on, so plan renders as few large batches instead of many small rounds.
---

# Batch ComfyUI work

You run on **Strata**, a local LLM, and ComfyUI renders on the **same 16 GB
GPU**. They can't both be loaded, so the GPU is handed over automatically:

- When a ComfyUI job starts, your model is unloaded (about 1 s).
- Your next request after the jobs finish reloads it (about 30 s). Because
  unloading clears the cache, it also re-reads this whole conversation from
  the start, at roughly 1 minute per 30K tokens.

You don't manage any of this yourself, and nothing breaks if you don't batch.
But every round of "render, look, render again" pays that cost twice. Treat
the advice below as **best effort**: batch when it's natural, and don't bend
the task out of shape for it.

## How to batch

- **Queue everything for a round up front, then wait once.** Submit all
  prompts, seeds and variants to `/prompt` first, then poll `/history` until
  all of them are done. Don't submit a job, wait for it, then submit the next:
  ComfyUI's queue goes empty between jobs, and the GPU can be handed back to
  you in that gap.
- **Over-generate instead of re-rolling.** If a panel or shot is risky, render
  more seeds (e.g. 6–8 instead of 3) and a few prompt variants of it in the
  same batch. Picking from extras is cheaper than a second round.
- **Plan all steps before the first render.** Write every prompt for the
  whole job (all panels, all shots) before submitting anything, so one batch
  covers it.
- **Put review material in one image.** After a batch, build one contact sheet
  per round (a grid of thumbnails, labelled) and look at that, instead of
  opening every output.
- **Keep tool output short.** Have the render script print a one-line summary
  (`48 images → cand-*.jpg`), not per-step logs. Everything printed is re-read
  after each reload.
- **Do non-GPU work outside the batch.** Layout, captions, file moves and
  contact sheets don't need the GPU. Do them before you queue the batch or
  after you've reviewed it, not between jobs.

## When a single job is right

One job at a time is fine when the next prompt really depends on the result,
for example tuning one parameter step by step, or when the user asked for
exactly one image. Say so in your reply if you expect several rounds.

## If a job fails with "GPU busy"

A job that fails with `GPU busy, job not run: …` means your model was busy
when ComfyUI tried to take the GPU, for instance another conversation is
using it. Wait a little and queue the job again. Don't retry in a tight loop.
