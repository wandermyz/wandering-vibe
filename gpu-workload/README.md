# gpu-workload → vhotseat

**vhotseat moved to its own repository:
[~/Projects/vhotseat](../../vhotseat) ·
[github.com/wandermyz/vhotseat](https://github.com/wandermyz/vhotseat).**
Its history up to 2026-10-18 was carried over with `git filter-repo`
(phase 3 of [the plan](docs/plans/2026-10-14-vhotseat.md)).

What stays here is the history of the move. `strata-model` is in
[strata-utils](../strata-utils/).

| Path | What |
| --- | --- |
| [docs/plans/](docs/plans/) | The vhotseat plan and the upstream IndexTTS fix |
| [docs/reports/](docs/reports/) | Progress reports |
| [docs/revert-gpu-workload.md](docs/revert-gpu-workload.md) | How to go back to the old `gpu-workload` script |

## Live install on this machine

| What | Points at |
| --- | --- |
| `~/.local/bin/vhotseat` | `~/Projects/vhotseat/vhotseat` |
| `~/.local/bin/comfy-render` | `~/Projects/vhotseat/comfy-render` |
| `~/Codebase/ComfyUI/custom_nodes/vhotseat_guard` | `~/Projects/vhotseat/integrations/comfyui/vhotseat_guard` |
| comfy-workspace's `comfyui-batching` pi skill | `~/Projects/vhotseat/kit/skills/comfyui-batching` |
| Strata's `before_load` | `~/.local/bin/vhotseat gate strata` (unchanged) |
| Config | `~/.config/vhotseat/config.yaml` |
| State | `~/.local/state/vhotseat/` |
