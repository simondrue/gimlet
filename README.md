# gimlet

A Mac menu bar tool for running VS Code on GenomeDK compute nodes instead of the login node.

On GenomeDK, VS Code Remote-SSH sessions must not run on the shared login node; they belong on a compute node with its own CPUs and memory. Doing that by hand means starting a Slurm job, finding which node it landed on, and pointing ssh at it — and forgotten jobs keep running and take up resources. gimlet does this from the menu bar: pick a job size, wait for it to start, and open VS Code directly on the compute node. It shows your jobs at a glance and lets you stop them with one click.

- The icon is a small pill with a colored dot. It shows how many jobs you have running (green), `N +1` when one is waiting in the queue (orange), or `0` (grey). When you need to log in or GenomeDK is not answering, it turns red and says `log in` or `offline`.
- Each job gets a stable ssh host name, `gimlet-1`, `gimlet-2`, … which any VS Code window can connect to.
- A job ends itself after 60 minutes with no VS Code connected, or when it hits its time limit. You can also stop it from the menu bar.

**The name:** a [gimlet](https://en.wikipedia.org/wiki/Gimlet_(tool)) (Old French *guimbelet*, probably "little *wimble*", from Middle Low German *wiemel*, a boring tool) is a small hand drill with a screw tip. Carpenters use it to bore a quick pilot hole, so the screw goes in straight without splitting the wood. This gimlet bores a small tunnel into a compute node on GenomeDK, so VS Code goes in cleanly without straining the login node. No hand-run scripts needed. The gimlet is also a delicious [drink](https://www.diffordsguide.com/cocktails/recipe/831/gimlet-diffords-recipe) — cheers 🍸

## Install

```sh
git clone <this repo> ~/git_repos/gimlet
~/git_repos/gimlet/install.sh
```

The installer:

1. installs [SwiftBar](https://github.com/swiftbar/SwiftBar) with Homebrew into `~/Applications` (on an AU Mac, Heimdal blocks new software, so request elevation in Heimdal first),
2. asks for your GenomeDK username and Slurm account and writes `~/.config/gimlet/settings`,
3. adds `Include ~/.config/gimlet/ssh_config` to the top of `~/.ssh/config` (backup in `~/.ssh/config.before-gimlet`),
4. puts the menu bar plugin in SwiftBar's plugin folder (`~/SwiftBar` unless you already have one),
5. adds SwiftBar to your login items and starts it,
6. sends a test notification, so macOS asks whether SwiftBar may send notifications. Allow it: gimlet uses notifications to say when a job starts or is about to hit its time limit. If you missed the prompt, turn them on in System Settings → Notifications → SwiftBar.

To do it by hand: install SwiftBar, copy `settings.example` to `~/.config/gimlet/settings` and fill it in, run `./gimlet ssh-config`, add the Include line to the top of `~/.ssh/config`, and put a plugin file called `gimlet.2m.sh` in SwiftBar's plugin folder containing `exec /path/to/gimlet menu`.

If you move the repo, run `install.sh` again. To remove gimlet, run `uninstall.sh`.

## Use

1. Click the icon → **Log in to GenomeDK…**. A Terminal window opens. Type your 2FA code if asked. The login uses your usual SSH key (`~/.ssh/id_ed25519` by default, change it in **Settings…**). If you don't have one set up for GenomeDK yet, follow [Public-key authentication](https://genome.au.dk/docs/getting-started/#public-key-authentication) in the GenomeDK docs.
2. **Start new job** → single / double / pitcher / shot, or **Custom order…** to type cores, memory, time limit and GPUs in a form. GPU jobs run on `gpu-short`, for at most 2 hours. The icon turns orange while the job waits, and a notification tells you when it runs. Only one job can wait at a time: **Start new job** is greyed out until it runs.
3. On the job (🍸 in use, 💤 unused, ⏳ waiting) → **Open VS Code**. A VS Code window opens on the node; use File → Open Folder to browse GenomeDK. Or in VS Code, pick `gimlet-1` from Remote-SSH's host list.
4. Close your VS Code windows when done. The job ends by itself 60 minutes after the last VS Code window closes (change this with idle minutes in **Settings…**), or stop it from the menu. **Stop all jobs?** stops every job.

Work still running on the node when the job ends (including tmux) is killed. Use `sbatch` for long runs.

**Settings…** opens a form for username, account, login host, ssh key, time limit and idle minutes. Presets and partition are edited in `~/.config/gimlet/settings`: the form's **Edit presets in file…** opens it in a text editor.

The same commands work in a terminal: `./gimlet list`, `./gimlet start single`, `./gimlet start custom 6 12 24:00:00 0`, `./gimlet open gimlet-1 /some/folder`, `./gimlet stop <jobid>`, `./gimlet stop-all`, `./gimlet settings`, `./gimlet doctor`.

When the repo tracks a git remote, the menu checks it once a day and shows **Update gimlet** when there are new commits. To check now, run `./gimlet check-update`.

## Troubleshooting

If something doesn't work, run `./gimlet doctor`. It checks each part of the setup (settings, ssh key, ssh config, VS Code and its Remote-SSH extension, SwiftBar, login, Slurm account) and says how to fix what is missing.

If the menu is slow to react to clicks: SwiftBar runs gimlet through your login shell, so a slow `~/.bash_profile` (e.g. `conda init`) delays every click. In SwiftBar's settings, set **Shell** to zsh.

If the icon stops updating until you open the menu, quit and reopen SwiftBar.

## How it works

| Piece | What it does |
|---|---|
| `gimlet` | All logic: menu output, start/stop, opening VS Code, and the ssh helper that finds a slot's node. |
| `gimlet-form.js` | The Custom order and Settings forms. |
| `gimlet-pill.js` | Draws the menu bar icon. |
| `gimlet-job.sh` | The Slurm job. Every minute it checks for your ssh connections on its node; after `IDLE_MINUTES` without one, it exits. It reports connected/idle in a small file, `~/.gimlet/<jobid>` on GenomeDK, which the menu reads; the file is removed when the job ends. |
| `~/.config/gimlet/ssh_config` | Generated. `gimlet-login` keeps one shared connection to the login node; `gimlet-*` connects to a job's node through it. Running jobs are also listed by name, so VS Code's host list shows them. |

Jobs appear in `squeue` as `gimlet-1`, `gimlet-2`, … with the preset as their comment. Job output is discarded.
