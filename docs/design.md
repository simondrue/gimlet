# gimlet — design

Status: agreed 2026-09-30. Background research: [research/01-problem-and-landscape.md](research/01-problem-and-landscape.md).

## Problem

On GenomeDK, VS Code Remote-SSH sessions must run on a compute node, not the login node. Today this means hand-run scripts to start a Slurm job and point ssh at its node, and jobs that are forgotten keep running.

gimlet is a macOS menu bar tool that starts, shows and stops these jobs, and lets any VS Code window attach to any of them.

## Form

- A **SwiftBar plugin** written in shell, so users can read and change it.
- Launches at login (SwiftBar setting).
- Installed with `install.sh` (installs SwiftBar via brew, links the plugin, asks for username and account). A README documents the manual steps.
- Not chosen: a native Swift app (it could wrap the same scripts later), Python/rumps, xbar (both unmaintained).

## Menu bar icon

A number in a circle (SF Symbol) = running jobs, plus `+N` for jobs waiting in the queue.

| Colour | Meaning |
|---|---|
| 🟢 green | all jobs running |
| 🟠 orange | at least one job waiting in the queue |
| ⚪ grey | no jobs |
| 🔴 red | logged out; needs a 2FA login |

## Menu

```
gimlet-1 · small · s21n34 · 9h12m left · 🔌 connected
   ├ Open in VS Code ▸  favourites / recent / Other…
   ├ Copy host name
   └ Stop job
gimlet-2 · large · waiting (queue)
   └ Cancel
───
Start new job ▸  small / medium / large
Settings…
Log in to GenomeDK        (only when the connection is down)
```

- **Stop job** asks for confirmation only if a VS Code window is connected.
- **Open in VS Code** runs `code --remote ssh-remote+gimlet-N <folder>`.
  - Favourites: the 5 folders the app has opened most often (counted automatically).
  - Recent: the latest folders opened through the app.
  - Other…: type a path.

## Settings

| Setting | Default |
|---|---|
| GenomeDK username | — (asked at install) |
| Slurm account | — (asked at install; e.g. `MomaDiagnosticsHg38`) |
| Partition | none |
| Presets | small 2 CPU / 4G, medium 4 / 8G, large 8 / 16G |
| Time limit | `12:00:00` (all presets) |
| Idle minutes before auto-stop | 60 |

Settings live in a plain config file. **Settings…** opens it or asks simple dialog questions.

## Jobs

- Submitted with `sbatch`, job name `gimlet`. The app lists and manages **only** jobs with this name. Old `tunnel` jobs are ignored.
- Each job gets the lowest free slot: `gimlet-1`, `gimlet-2`, … Slot names are reused, so VS Code's recent list keeps working.
- New jobs pass `--exclude=<nodes of existing gimlet jobs>`. Two jobs on one node would make idle detection unreliable.
- **A job ends when**:
  1. it is stopped from the menu,
  2. it hits its time limit, or
  3. **idle**: no ssh connection from the user to its node for *idle minutes*. A watchdog loop inside the job script checks this and exits. Losing the connection (e.g. the Mac sleeping) counts as idle.
- Work left running on the node (including tmux) dies with the job. Long runs belong in `sbatch`.
- GenomeDK allows ssh to a node only while the user has a job there, so the VS Code server is cleaned up when the job ends.

## Notifications

- When a waiting job starts running.
- About 15 min before a job's time limit.

## SSH

- gimlet owns one file (e.g. `~/.ssh/gimlet/config`), pulled in by an `Include` line in `~/.ssh/config`. The user's own config is otherwise untouched.
- That file holds a fixed `Host gimlet-*` entry. A small helper (a ProxyCommand) looks up the slot's node through `squeue` when you connect and **refuses** if that slot has no running job. The file is never rewritten.
- One shared login connection (ControlMaster/ControlPersist) through the login node is used by the plugin's status checks and by all VS Code windows.
- After a network change the shared connection dies and GenomeDK asks for 2FA again. The icon turns red, and **Log in to GenomeDK** opens Terminal so the code can be typed once. Status checks never prompt.

## Ruled out

- `code tunnel`: routes traffic through Microsoft servers, needs a GitHub/Microsoft login and internet on the node.
- Reading VS Code's internal recent-folders store: internal format, may break.
- Tracking VS Code windows on the Mac: idle is detected on the node instead.

## Open implementation details

- Exact check for "user has an ssh connection to this node" in the watchdog (e.g. user-owned `sshd` processes on the node, or `who`).
- Status check interval (≈15–30 s) and how "connected" is shown per job.
- Whether SwiftBar's notification support covers both notifications, or `osascript` is needed.
