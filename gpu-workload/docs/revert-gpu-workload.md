# Reverting from vhotseat to gpu-workload

On 2026-10-17 the GPU handover moved from the `gpu-workload` script to
`vhotseat` (PRs #37 phase 0, #38 phase 1, and the switchover that removed
`gpu-workload`). If vhotseat misbehaves, this puts the machine back on the last
`gpu-workload` that ran it.

## What changed on the machine

| Thing | Before (gpu-workload) | After (vhotseat) |
| --- | --- | --- |
| Strata's hook | `before_load: ["/home/wander/.local/bin/gpu-workload", "hook", "strata-before-load"]` in `~/Codebase/Strata/strata-iq2_xs.json` and `strata-iq3_xxs.json` | `["/home/wander/.local/bin/vhotseat", "gate", "strata"]`. Backups: `strata-*.json.pre-vhotseat` |
| ComfyUI guard | `custom_nodes/gpu_workload_guard`, runs `gpu-workload switch comfy --wait 300`; env `GPU_WORKLOAD_GUARD*` | `custom_nodes/vhotseat_guard` → `gpu-workload/comfyui/vhotseat_guard`, runs `vhotseat switch comfy --wait 300`; env `VHOTSEAT_GUARD*`, `VHOTSEAT_BIN` (none set) |
| CLI | `~/.local/bin/gpu-workload` → `gpu-workload/gpu-workload` | `~/.local/bin/vhotseat` → `gpu-workload/vhotseat`; `gpu-workload` removed |
| Config | none; `GPU_WORKLOAD_*` env vars | `~/.config/vhotseat/config.yaml` |
| State | `~/.local/state/gpu-workload/` | `~/.local/state/vhotseat/`; the old path is a symlink to it. The lock is still `switch.lock`, so either tool takes the same lock. |
| wandering-gallery | `generate.gpuWorkload` unset (runs `gpu-workload`) | `generate.gpuWorkload: /home/wander/.local/bin/vhotseat` in `~/.config/wandering-gallery/config.yaml` |
| strata-model env | `GPU_WORKLOAD_STRATA_URL` / `_UNIT` | `STRATA_URL` / `STRATA_UNIT` (none of them were set) |

The last commit with a working `gpu-workload` and no config is **`578b121`**
(phase 0 merged: the refactor with the same CLI). The one before any refactor
is **`3eaad1a`**.

## Revert (about 2 minutes)

**Since 2026-10-18 the leftovers this relied on are deleted**: the
`strata-*.json.pre-vhotseat` backups and the `~/.local/state/gpu-workload`
symlink. In step 2, edit `before_load` by hand to
`["/home/wander/.local/bin/gpu-workload", "hook", "strata-before-load"]`
instead of copying a backup, and first recreate the state link:
`ln -s vhotseat ~/.local/state/gpu-workload`.

Do it while nothing is rendering (`vhotseat status`: 0 running / 0 queued).

```sh
cd ~/Projects/wandering-vibe

# 1. A checkout of the last gpu-workload, outside the main tree
git worktree add ~/Projects/gpu-workload-rollback 578b121
ln -sfn ~/Projects/gpu-workload-rollback/gpu-workload/gpu-workload ~/.local/bin/gpu-workload

# 2. Strata's hook back to gpu-workload, then restart it (it reads before_load
#    only at startup). Unload first so nothing is cut off.
cd ~/Codebase/Strata
for f in iq2_xs iq3_xxs; do cp strata-$f.json.pre-vhotseat strata-$f.json; done
curl -s -X POST -H 'Content-Type: application/json' 'localhost:2335/unload?wait=300' -d '{}'
systemctl --user restart strata

# 3. The ComfyUI guard from the same checkout (old name), then restart ComfyUI.
#    Remove the new one: both installed would each take the GPU before every job.
rm ~/Codebase/ComfyUI/custom_nodes/vhotseat_guard
ln -sfn ~/Projects/gpu-workload-rollback/gpu-workload/comfyui/gpu_workload_guard \
        ~/Codebase/ComfyUI/custom_nodes/gpu_workload_guard
systemctl --user restart comfyui

# 4. wandering-gallery: remove the `gpuWorkload:` line under `generate:` in
#    ~/.config/wandering-gallery/config.yaml, then
systemctl --user restart wandering-gallery

# 5. Keep vhotseat's config out of the way (578b121 doesn't read it, but a later
#    checkout would)
mv ~/.config/vhotseat/config.yaml ~/.config/vhotseat/config.yaml.off
```

The state directory needs nothing: `~/.local/state/gpu-workload` already
points at the same log and lock.

## Check it

```sh
gpu-workload status
journalctl --user -u strata -n 50 | grep "before loading"   # after the next Strata load:
                                                            # …/gpu-workload hook strata-before-load
journalctl --user -u comfyui -n 300 | grep gpu_workload_guard   # on (…/gpu-workload, wait 300s)
python3 ~/Projects/gpu-workload-rollback/gpu-workload/comfyui/smoke_job.py   # success
```

## Partial revert

Strata's hook and the guard are independent: either can run either tool, and
both take the same lock (`switch.lock` in the shared state directory). So one
side can go back alone, e.g. only step 2 if Strata's gate misbehaves.

## Going forward again

Undo the steps: `before_load` back to `vhotseat gate strata` (the current
files; keep a copy before step 2), remove `custom_nodes/gpu_workload_guard` and
link `custom_nodes/vhotseat_guard` →
`~/Projects/vhotseat/integrations/comfyui/vhotseat_guard` (vhotseat moved
to its own repo on 2026-10-17), `~/.local/bin/vhotseat` → `~/Projects/vhotseat/vhotseat`, the
config back in place, restart both, `vhotseat doctor`. Then
`git worktree remove ~/Projects/gpu-workload-rollback`.
