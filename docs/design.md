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
   ├ Open VS Code
   └ Stop job
gimlet-2 · large · waiting (queue)
   └ Cancel
───
Start new job ▸  small / medium / large
Settings…
Log in to GenomeDK        (only when the connection is down)
```

- **Stop job** asks for confirmation only if a VS Code window is connected.
- **Open VS Code** runs `code --new-window --remote ssh-remote+gimlet-N`: an empty window on the node, where File → Open Folder browses GenomeDK. (Favourite and recent folder lists were dropped: browsing is easier than remembering paths, and VS Code's own recent list covers reopening.)

## Settings

| Setting | Default |
|---|---|
| GenomeDK username | — (asked at install) |
| Slurm account | — (asked at install; e.g. `MomaDiagnosticsHg38`) |
| Partition | none |
| Presets | small 2 CPU / 4G, medium 4 / 8G, large 8 / 16G |
| Time limit | `12:00:00` (all presets) |
| Idle minutes before auto-stop | 60 |

Settings live in a plain config file (`~/.config/gimlet/settings`). **Settings…** opens it in a text editor.

## Jobs

- Submitted with `sbatch`. The job name is its slot, `gimlet-1`, `gimlet-2`, … (the lowest free one), and the preset goes in the job comment. The app lists and manages **only** jobs named `gimlet-N`. Old `tunnel` jobs are ignored.
- Slot names are reused, so VS Code's recent list keeps working.
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

- gimlet owns one file (`~/.config/gimlet/ssh_config`), pulled in by an `Include` line in `~/.ssh/config`. The user's own config is otherwise untouched.
- That file holds a fixed `Host gimlet-*` entry. A small helper (a ProxyCommand) looks up the slot's node through `squeue` when you connect and **refuses** if that slot has no running job. The file only changes when the settings do.
- One shared login connection (ControlMaster/ControlPersist) through the login node is used by the plugin's status checks and by all VS Code windows.
- After a network change the shared connection dies and GenomeDK asks for 2FA again. The icon turns red, and **Log in to GenomeDK** opens Terminal so the code can be typed once. Status checks never prompt.

## Ruled out

- `code tunnel`: routes traffic through Microsoft servers, needs a GitHub/Microsoft login and internet on the node.
- Reading VS Code's internal recent-folders store: internal format, may break.
- Tracking VS Code windows on the Mac: idle is detected on the node instead.

## Implementation choices

- Watchdog: counts user-owned `sshd: user@…` / `sshd-session: user@…` processes on the node once a minute, and reports `<preset> connected` / `<preset> idle N` in its own job comment (`scontrol update`, only when it changes). The menu reads it with `squeue`, so nothing is stored on GenomeDK. Job output goes to `/dev/null`.
- The menu refreshes every 15 s (plugin file `gimlet.15s.sh`).
- Notifications use `osascript display notification`.
- Status checks first test the shared connection (`ssh -O check`) and never open a new login, so a logged-out menu doesn't cause repeated failed logins.
