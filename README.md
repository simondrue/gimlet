# gimlet

A Mac menu bar tool for running VS Code on GenomeDK compute nodes instead of the login node.

On GenomeDK, VS Code Remote-SSH sessions must not run on the shared login node; they belong on a compute node with its own CPUs and memory. Doing that by hand means starting a Slurm job, finding which node it landed on, and pointing ssh at it — and forgotten jobs keep running and use up your allocation. gimlet does this from the menu bar: pick a job size, wait for it to start, and open VS Code on it. It shows your jobs at a glance and lets you stop them with one click.

- The icon shows how many jobs you have running (green), a `+N` when some are waiting in the queue (orange), or red when you need to log in.
- Each job gets a stable ssh host name, `gimlet-1`, `gimlet-2`, … which any VS Code window can connect to.
- A job ends itself after 60 minutes with no VS Code connected, or when it hits its time limit (12 h).

**The name:** a gimlet (Old French *guimbelet*, likely from Middle Dutch *wimmelkijn*, "little auger") is a small hand drill with a screw tip and a twist handle. Carpenters use it to bore a quick pilot hole, so the screw goes in straight without splitting the wood. No power drill needed. This gimlet does the same for GenomeDK: it bores a small tunnel into a compute node, so VS Code goes in cleanly without straining the login node. No hand-run scripts needed. The gimlet is also a drink — cheers 🍸

Design and background: [docs/design.md](docs/design.md), [docs/research/](docs/research/).

## Install

```sh
git clone <this repo> ~/git_repos/gimlet
~/git_repos/gimlet/install.sh
```

The installer:

1. installs [SwiftBar](https://github.com/swiftbar/SwiftBar) with Homebrew into `~/Applications` (no admin password needed),
2. asks for your GenomeDK username and Slurm account and writes `~/.config/gimlet/settings`,
3. adds `Include ~/.config/gimlet/ssh_config` to the top of `~/.ssh/config` (backup in `~/.ssh/config.before-gimlet`),
4. puts the menu bar plugin in SwiftBar's plugin folder (`~/SwiftBar` unless you already have one),
5. adds SwiftBar to your login items and starts it.

To do it by hand: install SwiftBar, copy `settings.example` to `~/.config/gimlet/settings` and fill it in, run `./gimlet ssh-config`, add the Include line to the top of `~/.ssh/config`, and put a plugin file called `gimlet.2m.sh` in SwiftBar's plugin folder containing `exec /path/to/gimlet menu`.

If you move the repo, run `install.sh` again.

## Use

1. Click the icon → **Log in to GenomeDK…**. A Terminal window opens. Type your 2FA code if asked. The login is shared by the menu and all VS Code windows until your network changes.
2. **Start new job** → shot / double / pitcher. The icon turns orange while the job waits, and a notification tells you when it runs.
3. On the job → **Open VS Code**. A VS Code window opens on the node; use File → Open Folder to browse GenomeDK. Or in VS Code, pick `gimlet-1` from Remote-SSH's host list.
4. Close your VS Code windows when done. The job ends by itself 60 minutes later, or stop it from the menu.

Work still running on the node when the job ends (including tmux) is killed. Use `sbatch` for long runs.

**Settings…** opens `~/.config/gimlet/settings` in a text editor, where you can change presets, time limit, idle minutes, account and partition.

The same commands work in a terminal: `./gimlet list`, `./gimlet start shot`, `./gimlet open gimlet-1 /some/folder`, `./gimlet stop <jobid>`.

## How it works

| Piece | What it does |
|---|---|
| `gimlet` | All logic: menu output, start/stop, opening VS Code, and the ssh helper that finds a slot's node. |
| `gimlet-job.sh` | The Slurm job. Every minute it checks for your ssh connections on its node; after `IDLE_MINUTES` without one, it exits. It reports connected/idle in a small file, `~/.gimlet/<jobid>` on GenomeDK, which the menu reads; the file is removed when the job ends. |
| `~/.config/gimlet/ssh_config` | Generated. `gimlet-login` keeps one shared connection to the login node; `gimlet-*` connects to a job's node through it. Running jobs are also listed by name, so VS Code's host list shows them. |

Jobs appear in `squeue` as `gimlet-1`, `gimlet-2`, … with the preset as their comment. Job output is discarded.
