# vhotseat: progress report

2026-10-18 · Covers 2026-10-14 to 2026-10-18 · Plan:
[docs/plans/2026-10-14-vhotseat.md](../plans/2026-10-14-vhotseat.md)

## Summary

`gpu-workload`, a single 630-line script that handed this machine's GPU between
Strata (the local LLM) and ComfyUI, is now **vhotseat**. It's a configurable
Python package that takes turns on one GPU between any number of workloads,
and it never interrupts running work. It runs this machine today:

- Strata's pre-load hook is `vhotseat gate strata`.
- The ComfyUI guard node runs `vhotseat switch comfy`.
- The wandering-gallery dashboard calls `vhotseat` for status and before
  generating.

`gpu-workload` is removed. The way back to it is documented and backed up.

Phases 0, 1 and 2 of the plan are done. Phase 3, the open-source release, is
next.

| | Before (2026-10-14) | Now |
| --- | --- | --- |
| Code | 1 script, 630 lines, Strata and ComfyUI hard-coded | `vhotseat` package: about 2,000 lines in 17 modules, workloads described in `config.yaml` |
| Tests | none | 120 tests (about 1,700 lines) against fake Strata and ComfyUI servers; no GPU needed |
| Add a workload | edit the script | config only (`http` driver), or a Python driver; a proxy for servers with no hook |
| Memory safety | restart ComfyUI if it holds > 4 GiB | admission per workload and per model: Strata must be able to get 40–46 GiB of RAM before it loads |
| Checks | `status` | `status`, `doctor` (config, GPU, services, every gate installed, local patches), `doctor --exercise` (a real cycle, timed) |
| GPU reads | 2 × `nvidia-smi` per check, VRAM matched by path | NVML, VRAM matched by systemd unit |

## Pull requests

| PR | Merged | What |
| --- | --- | --- |
| #32 | 10-17 | The plan: design, extension points, agent kit, Windows notes, phases, self-review appendix, mermaid diagrams |
| #37 | 10-17 | **Phase 0**: split into the `vhotseat` package with the same CLI; first 53 tests; two bug fixes |
| #38 | 10-17 | **Phase 1**: `config.yaml`, generic `http` driver, admission, NVML, `vhotseat` CLI, `doctor`, comfy-render cleanup |
| #39 | 10-17 | **Switchover**: Strata, ComfyUI and the dashboard moved to `vhotseat`; `gpu-workload` removed; revert doc |
| #40 | 10-18 | Admission per model; guard renamed `vhotseat_guard` |
| #41 | 10-18 | **Phase 2**: `doctor --exercise`, `patches:`, the proxy API and guide, the add-workload skill, the llama-server trial and its fixes |
| #42 | 10-18 | A gate for an already-loaded workload doesn't count its own memory |
| wandering-gallery #24 | 10-18 | Dashboard: vhotseat replaces gpu-workload; an idle GPU shows as "Free" |

Related, outside this repo: our IndexTTS unload fix was merged into TTS Audio
Suite (PR #373, released in 5.10.4), so the local patch we carried is gone.

## What was built

### The core (phases 0–1)

- **Arbiter.** One `acquire()` algorithm for every handover:
  1. release the other workloads, waiting for their running work and never
     interrupting it;
  2. restart an idle workload if releasing isn't enough;
  3. check the incoming workload's admission;
  4. load it.
- **Gates.** Each workload asks for the GPU through a gate:
  - `hook`: Strata runs `vhotseat gate strata` before every load;
  - `plugin`: the ComfyUI guard node takes the GPU before every job;
  - `proxy`: for servers with no hook; see the guide below;
  - `hold`: a command run under `vhotseat hold NAME -- CMD`.
- **One lock per GPU,** with a note of what its holder is doing, so a hook that
  fires inside a switch's own load never deadlocks against it.
- **`config.yaml`,** validated so that every error names the key. A broken
  config makes gates refuse rather than let a load through unchecked.
- **Drivers:** a generic `http` driver, so Strata is config only, and a
  `comfyui` driver for `/queue`, `/free`, and the restart with its history
  settle.
- **Admission:**
  - `min_available_ram_mib` (measured against `MemAvailable`, which counts
    reclaimable cache) and `min_free_vram_mib`;
  - `by_model`, which picks the figures for the model about to load: Strata
    reports its model even while unloaded;
  - releasing the other workloads always happens; admission only decides
    whether vhotseat also restarts one, and whether the load is allowed.

### Extensibility (phase 2)

- **`doctor --exercise NAME`:** runs a real take, load, release and confirm
  cycle on one workload, timed. On this machine: Strata loads in 31 s and
  releases in 1.3 s; ComfyUI frees 7 GB in 1 s.
- **`patches:`:** local fixes to other projects' code. `doctor` checks each one
  is still applied, and says when the installed version already contains the
  fix. It did that with TTS Audio Suite 5.10.4, reporting the patch could go
  before anyone looked.
- **`vhotseat.api`:** the library for a long-running gate. Its fast path is one
  file read while the GPU hasn't changed hands (a per-GPU handover counter).
  `release.pre` lets a proxy drain its requests before an unload.
- **`docs/guides/proxy-gate.md`:** how to build a proxy gate. It's a procedure
  with a check at each step, a 7-item test list, known traps (including
  llama-server's router mode), and an Ollama walkthrough. Its sample config is
  run as a test.
- **`kit/skills/vhotseat-add-workload`:** the procedure a coding agent follows
  to add any server.

### The llama-server trial

A fresh agent, given only the skill, the guide and the docs, added llama-server
(llama.cpp, Qwen3 1.7B) as a third workload behind a proxy it wrote. Every
check passed:

- `--exercise`: load 1.0 s, release 0.3 s;
- taking turns with ComfyUI, in both directions;
- a streamed answer was never cut off;
- the proxy added 0.36 ms per request;
- 10 requests at once caused one handover;
- the proxy was killed mid-stream and recovered.

**Conclusion:** the documentation is enough for an agent to add a new server.
The agent's proxy was left out of the repo, as planned; the guide is what
ships.

## Bugs found and fixed

Most of these were found by the new tests or the trial, not by users. The
"seen live" column says whether any of them actually happened in normal use.

| Bug | Found by | Seen live? |
| --- | --- | --- |
| `hold comfy` and the ComfyUI guard waited on each other, for up to 420 s | Self-review of the design | No: all holds in the log predate the guard |
| An unreachable ComfyUI `/queue` counted as idle (should be unknown, so refuse) | Self-review | No |
| `switch comfy` with nothing loaded reported failure | Removing the compatibility layer | No: the old CLI hid it |
| A burst of requests made one handover each instead of one | `vhotseat.api` tests | No: nothing used the API yet |
| **`switch X --wait` held the lock while waiting for ComfyUI's queue, stalling the batch for the whole wait** | The llama-server trial | No: nothing runs `switch strata --wait` during a batch, but a cron job or a person could have |
| A manual `gate` with Strata loaded counted its own memory and restarted ComfyUI | Running it by hand while writing this report | Once, by me; no work lost |
| Strata got oomd-killed after loading on top of an idle ComfyUI under the old 4 GiB threshold | systemd-oomd, 2026-10-16 | **Yes** (before this project's code): fixed by admission per workload |

## Mistakes made along the way

In the interest of a faithful record:

- **Editing the live checkout.** A syntax error I introduced broke `vhotseat
  doctor` for under a minute. The gate and switch paths don't import that file,
  so they were unaffected. Since then, work happens in worktrees.
- **Copying a config early.** I copied a config with a new `patches:` key into
  place while the live code didn't know it yet. Every gate would have refused,
  making Strata answer 503, for a few minutes. The event log shows no refused
  load in that window. The phase 2 notes now say to copy the config only after
  merging, and a test checks the example config always validates.
- **A stray server.** The first trial agent was cut off with the session and
  left a llama-server it had started by hand running outside its unit, holding
  3 GB of VRAM no gate knew about, for about 5 minutes. Nothing collided. The
  skill now forbids starting servers outside their unit, and `doctor` warns
  about unattributed VRAM.
- **A model loop in one pi test run** (not a vhotseat fault): the model
  repeated the same tool call about 155 times instead of answering. A rerun
  was clean.

## Verification on this machine

- `vhotseat doctor`: all checks ok (GPU, RAM, both services, both APIs,
  Strata's hook, the guard node, Strata's admission for its current model).
- **Full pi flow,** Strata → ComfyUI → Strata → ComfyUI → Strata (two render
  rounds, four handovers): passed on phase 0, phase 1, and after the
  switchover.
- **wandering-gallery dashboard:** status card and a real generation through
  its API, plus 39 Playwright tests and the iOS API contract check.
- **Event log** since 2026-10-13: 280 Strata load decisions, 213 switches,
  5 exercises.

## Current state

- **Live:** `~/.local/bin/vhotseat` → `gpu-workload/vhotseat` on `main`.
  Config `~/.config/vhotseat/config.yaml`, a copy of `config.example.yaml`.
  State in `~/.local/state/vhotseat/`, with the old path symlinked to it.
- **Backups for going back:** `strata-*.json.pre-vhotseat`,
  `~/.config/wandering-gallery/config.yaml.pre-vhotseat`,
  `~/.config/vhotseat/config.yaml.pre-by-model`. The steps are in
  [revert-gpu-workload.md](../revert-gpu-workload.md).
- **Scratch:** `~/scratch/llama` (about 2.4 GB) holds the llama.cpp build, the
  test model and the trial proxy. The `llama-server` unit is stopped and not in
  the config. All of it can be deleted.

## Open items

- **iOS dashboard:** show "Free" for an idle GPU (wandering-gallery parity ID
  DASH-05, one line in `DashboardGpu.swift`); needs the Mac.
- **Strata upstream asks** (plan §11): an in-flight count, so vhotseat doesn't
  learn that Strata is busy from a 409 on unload; and documenting `/unload?wait`
  and `before_load` as stable.
- **ComfyUI upstream ask:** a public pre-execute hook. The guard wraps a
  private method, so every ComfyUI update needs `docs/comfyui-updates.md`.
- **Open questions** (plan §13): whether Ollama's `keep_alive: 0` cuts off a
  running stream; and saving and restoring Strata's prefix cache across an
  unload, which would remove the cost of re-reading the conversation after each
  handover.

## Next: phase 3, the open-source release (Linux)

1. Move `gpu-workload/` to a new `vhotseat` repo with `git filter-repo`,
   keeping the history, under the MIT licence. Leave a pointer behind.
2. Package for PyPI (`vhotseat`, with `comfy-render` as a second command), and
   publish the guard to the ComfyUI Registry as `vhotseat-guard`.
3. CI: lint and tests on Python 3.10–3.13.
4. The agent kit:
   - comfy-render with `--hold`;
   - the batching skill, made generic;
   - the setup, ComfyUI-update and VRAM-leak skills.
5. Docs: a README built around "your local LLM agent drives ComfyUI on the
   same GPU", a generalized how-it-works, and a driver-authoring guide.
6. Keep personal things in wandering-vibe: yuki-conductor specifics, pi's
   settings, the Akine skill, this machine's measurements.

Phase 4 (Windows) needs a tester with an NVIDIA card on Windows.
