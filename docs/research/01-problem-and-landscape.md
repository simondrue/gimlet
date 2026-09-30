# 01 — Problem and landscape: VS Code on GenomeDK compute nodes

Researched 2026-09-30. Sources are cited inline as `[n]`, with the list at the bottom. "Inference" marks conclusions drawn from sources but not stated by them. "Unverified" marks things that need a test on GenomeDK.

## 0. Problem in one paragraph

VS Code Remote-SSH runs its server, extensions, language servers and terminals on whichever host it connects to. On GenomeDK the default is `login.genome.au.dk`, the shared frontend, which "should not be used for heavy computations" [G1][G6]. The goal is to get VS Code onto a Slurm compute node with little friction, to share that setup with a colleague (both on macOS), and to avoid forgotten jobs holding cores.

---

## 1. Existing solutions

### 1a. User's own: `~/vscode_ssh` [L1][L2][L3]

**How it works** (`setup_custom_config.sh`):
1. It runs `ssh GenomeDK "squeue -h -u $USER -n tunnel"` and **cancels any existing `tunnel` job**, so only one job exists at a time.
2. It runs `sbatch --account=… --time=12:00:00 --cpus-per-task=2 --mem=32G --job-name=tunnel --output=tunnel.out --error=tunnel.err --parsable --wrap='sleep infinity'` over ssh.
3. It polls `squeue -h -j $JOB_ID -t RUNNING` **once a second, with a new ssh connection each time**, and reads column 8 (the NODELIST) with awk.
4. It **overwrites** `~/vscode_ssh/genomeDK.config` with two hosts:
   - `GenomeDK-login`: `HostName login.genome.au.dk`, with User and IdentityFile.
   - `GenomeDK-compute`: `HostName <node>`, `ProxyJump GenomeDK-login`.
   
   Both have `StrictHostKeyChecking no`.
5. The main `~/.ssh/config` pulls that file in with `Include /Users/au468644/vscode_ssh/genomeDK.config` on its first line [L3].

**Node discovery:** squeue's default output format, column 8.

**ssh config approach:** a separate generated file loaded with `Include`. The alias `GenomeDK-compute` stays the same while its `HostName` changes. Every VS Code window aimed at `GenomeDK-compute` lands on the current job's node.

**Cleanup:** there is none beyond the next run cancelling the previous job, or the 12 h walltime running out.

**Weaknesses:**
- Only one job at a time, and re-running the script kills the old job along with any VS Code windows attached to it.
- Nothing ends the job when VS Code closes, so it holds 2 CPUs and 32 GB for up to 12 h.
- It opens one ssh connection per second while waiting, with no ControlMaster set [L3]. Each poll goes through a full login.
- Dead code: it computes a "time until Friday midnight" and then hard-codes `MAX_TIME="12:00:00"`.
- The awk column parsing breaks if the squeue format changes.
- `StrictHostKeyChecking no` turns off MITM protection for all these hosts.
- It uses two aliases for the same login host (`GenomeDK` in the main config and `GenomeDK-login` in the generated file).
- `Host *` / `User simond` in the main config applies that user name to **every** ssh host, not only GenomeDK [L3]. This is outside the tool, but worth noting.
- `tunnel.out` and `tunnel.err` land in `$HOME` on GenomeDK.

### 1b. Colleague's: `micknudsen/vscode-hpc` (commit `cfd6af8`, 2026-09-12) [C1][C2]

**How it works:** a single bash CLI.

`vscode-hpc open [--time --cpus --mem --partition --account] FOLDER` does the following:
1. Builds `sbatch --parsable --job-name=vscode --nodes=1 --ntasks=1 … --output=/dev/null --wrap='trap "exit 0" TERM INT; while :; do sleep 3600; done'` and runs it over `ssh user@login`.
2. Polls `squeue --noheader --jobs=ID --format='%T %N'` every 5 s.
3. Runs `code --remote ssh-remote+<NODE> FOLDER` [C2 L137-177].

Defaults come from `VSCODE_HPC_*` environment variables.

**ssh config approach:** the config is static and never rewritten. The user adds `Host cn-*` with `ProxyJump user@login…` once [C1 "Configure SSH"]. The node's real hostname is the VS Code host alias.

**Node discovery:** squeue `%N`.

**Cleanup:** manual. `vscode-hpc cancel [JOBID | --all] [--dry-run]` lists or cancels your jobs named `vscode` (`squeue --me --name=vscode`) [C2 L186-292]. Ctrl-C does *not* cancel the job [C2 L158]. The README says: "Always release the allocation when finished" [C1].

**Strengths:**
- One job per session, so several jobs can run in parallel.
- No config rewriting.
- It checks that the job ID is a number and that the job being cancelled is one of its own `vscode` jobs.

**Weaknesses:**
- Manual cleanup, so forgotten jobs are likely.
- Each window is tied to a node name. If two jobs land on the same node, they share one alias. See §3 (pam_slurm_adopt) for which job the ssh sessions end up in.
- A new ssh login for every poll and command, with no ControlMaster.
- You need a terminal and the `code` CLI on PATH.
- To reattach to an existing job you have to know its node name.
- Jobs have no identity beyond the name `vscode`.

### 1c. Comparison

| | User (`vscode_ssh`) | Colleague (`vscode-hpc`) |
|---|---|---|
| Jobs | 1, shared by all windows | 1 per `open` |
| ssh config | Generated file + `Include`, alias `GenomeDK-compute` | Static `Host cn-*` + ProxyJump |
| Opens VS Code | No (user picks the host) | Yes (`code --remote`) |
| Cleanup | The next run cancels the old job | `vscode-hpc cancel` |
| Idle auto-stop | No | No |

---

## 2. GenomeDK specifics

- **Login host:** `login.genome.au.dk` for SSH. `desktop.genome.au.dk` is the browser desktop [G1].
- **2FA:** mandatory. TOTP is set up with `gdk-auth-show-qr` [G1].
- **SSH keys:** documented using ed25519 created with `ssh-keygen -t ed25519 -q -N ""` (**no passphrase**) and `ssh-copy-id`. After that "You should now be able to log in to the cluster without typing your password" [G1].
  - The docs do **not** say whether key login skips the 2FA prompt.
  - *Inference:* the user's script makes one ssh call per second with no ControlMaster [L2][L3], which would be unusable if every login asked for a TOTP code. So key logins very likely skip 2FA. **Unverified.**
- **Frontend policy:** "should not be used for heavy computations. Instead, submit a job to the queuing system" [G1].
  - The newsletters repeat "do not run on the frontend" [G6], and the Desktop runs on the frontend, so "all of the usual guidelines about not running computations on the frontend still apply" [G7].
  - There is no VS Code-specific rule.
- **VS Code guidance:** none on genome.au.dk. The docs index has no VS Code page [G2]. The software-specific page covers Jupyter and RStudio only [G4].
  - For Jupyter, the official pattern is: start an interactive job, then from the laptop run `ssh -L<port>:<compute node>:<port> <user>@login.genome.au.dk` [G4].
  - So network access from the login node to compute nodes is expected to work.
- **SSH to compute nodes / pam_slurm_adopt:** **not documented** [G3][G4].
  - The documented way into a running job is `srun --jobid <job id> --overlap --pty bash` [G3].
  - *Empirical:* the user's `ProxyJump` → `cn-1040` setup and the colleague's `Host cn-*` setup both assume `ssh <node>` from the login node works while you have a job there [L1][C1]. Whether it also works **without** a job (meaning pam_slurm_adopt is absent) is **unverified**.
- **Accounts:** "When submitting jobs, you should always specify which account should be used". Jobs without an account get tight limits and errors like `AssocMaxWallDurationPerJobLimit` [G3]. Projects are managed with `gdk-project-*` [G5].
- **Limits:**
  - Max time per job: 7 days.
  - Max 3600 cores per user.
  - GPU jobs under 75 % utilisation after 2 h are killed. This matters if the app ever offers GPU sessions.
  - Partitions are listed with `gnodes`; the docs name none [G8].
- **Nodes:** CPU `cn-[1001-1110]`, GPU `gn-[1001-1004]` [G9]. A static `Host cn-* gn-*` pattern is therefore enough.
- **VPN / network:** not mentioned in the docs [G1]. **Unverified** whether off-campus access to `login.genome.au.dk` needs the AU VPN.
- **Closed zones** (iPSYCH, Brain) use NoMachine [G1], so this tool is realistically for the open zone only.

---

## 3. SSH mechanics (OpenSSH; macOS ships OpenSSH_10.3p1 on this machine [S0])

- **`Include`:**
  - Accepts globs and tokens.
  - Relative paths resolve to `~/.ssh`.
  - "may appear inside a Match or Host block".
  - Files are processed in lexical order [S1 Include].
  - Combined with "for each parameter, the first obtained value will be used" [S1 intro], this means that where the Include line sits decides precedence.
  - → The app should own one file (e.g. `~/.ssh/gimlet/config`) and add a single `Include` line near the top of `~/.ssh/config`, as the user already does.
- **`ProxyJump`:**
  - "first making an ssh(1) connection to the specified ProxyJump host and then establishing a TCP forwarding to the ultimate target".
  - It "will compete with the ProxyCommand option – whichever is specified first will prevent later instances of the other".
  - Config for the destination is "not generally applied to jump hosts" [S1 ProxyJump].
- **`ProxyCommand`:**
  - Runs via the shell's `exec`.
  - Reads stdin and writes stdout.
  - It "should eventually connect an sshd(8) server running on some machine, or execute sshd -i somewhere".
  - Host keys are checked against the `Hostname` [S1 ProxyCommand].
  - Tokens `%h %n %p %r`, where `%n` is "the original remote hostname, as given on the command line" [S1 TOKENS].
  - `ssh -W host:port` forwards stdio over the secure channel, which is the building block for a jump [S2 -W].
- **ControlMaster / ControlPath / ControlPersist:**
  - Several sessions share one connection. Later clients "fall back to connecting normally if the control socket does not exist".
  - `ControlPersist <time>` keeps the master in the background and ends it after it has been idle that long.
  - `ssh -O check|exit` controls the master [S1 ControlMaster/ControlPersist][S2 -O].
  - ControlPath should include `%C` or `%h %p %r` [S1].
  - The VS Code docs recommend exactly this for 2FA and password prompts: `ControlMaster auto`, `ControlPath ~/.ssh/sockets/%r@%h-%p`, `ControlPersist 600` [V1 "Enabling alternate SSH authentication methods"].
  - **For gimlet:** a persistent master to `login.genome.au.dk` lets the app poll `squeue` cheaply, and lets any ProxyJump/ProxyCommand hops reuse it. It also means at most one auth or 2FA prompt per ControlPersist window.
- **`BatchMode yes`:** turns off password and host-key prompts, which suits a background app [S1 BatchMode].
- **`ServerAliveInterval` / `ServerAliveCountMax`:** detect dead links [S1].

**Three ssh-config designs for gimlet:**

| Design | Config churn | Notes |
|---|---|---|
| A. Generated `Host gimlet-<jobid>` blocks with `HostName <node>` + `ProxyJump` in an Included file | Rewritten on each job change | Simple. Stale entries are possible if the app is not running when a job ends. |
| B. Static `Host cn-* gn-*` + `ProxyJump login` (colleague's) | None | The alias is the node, not the job. Two jobs on one node look identical. |
| C. Static `Host gimlet-*` + `ProxyCommand gimlet-proxy %n`, where the script parses the job ID from `%n`, runs `squeue -h -j ID -o %N` via the login master, then `exec ssh -W <node>:22 login` | None | Aliases are per job and never go stale in a harmful way (a dead job just fails to connect). Needs a helper script. Host-key checking is against the alias, so use `HostKeyAlias`/`StrictHostKeyChecking accept-new` [S1]. |

**pam_slurm_adopt caveat:**
- If GenomeDK uses it, ssh to a node is denied unless you have a job there, and the session is adopted into the job's `extern` step. Adopted processes are killed when the job ends [SL1].
- With several of your jobs on one node, the module tries to identify the source job. When that fails (as for connections from the login node), `action_unknown` defaults to **newest** [SL1].
- *Inference:* you cannot choose which of two same-node jobs a VS Code session lands in. Killing the newest job may kill windows the user thinks belong to the older one. **Unverified.**

**No-ssh-to-node variant:**
- `ProxyCommand ssh login "srun --jobid=ID --overlap … <user-run sshd -i>"` would ride on the documented `srun --overlap` [G3], with the `sshd -i` pattern from [S1].
- gmertes and AAU BioCloud show a user-run `sshd` inside a job working elsewhere [P1][P2].
- More moving parts. Only worth it if direct ssh to nodes is blocked.

---

## 4. VS Code Remote-SSH

- **Host selection:** hosts come from the ssh config, or from `remote.SSH.configFile` ("The absolute file path to a custom SSH config file") [V1 ssh.md L138][V3].
  - *Inference:* hosts in `Include`d files work, because VS Code runs the system `ssh`, which resolves the Include. This is how the user's current setup works [L3].
- **Open a window from the CLI:** `code --remote ssh-remote+remote_server /code/my_project`. You can also use `--folder-uri vscode-remote://ssh-remote+HOST/path` [V1 "Connect to a remote host from the terminal"]. The colleague's tool uses this [C2 L177].
- **Where the server runs:** "By default the server is installed in the home directory of every remote" (`~/.vscode-server`) [V3 serverInstallPath]. It runs as your user [V2 faq].
  - GenomeDK home is shared, so one install serves the login node and all compute nodes (*inference*).
  - NFS-style homes can break locking, so `remote.SSH.lockfilesInTmp` exists "for hosts with a home directory using NFS" [V3].
  - NERSC also recommends `"remote.SSH.useFlock": false` for compute nodes [P3].
- **Two connections per window:** VS Code opens one connection to install or start the server and a second for the port tunnel. On systems that route connections to different nodes, you need ControlMaster to keep both on one node [V1 "Connecting to systems that dynamically assign machines"]. This is relevant to any ProxyCommand that starts a job (§5, salloc variant).
- **Settings** [V3, extension v0.124.0 package.nls.json]:
  - `remote.SSH.useLocalServer` (default true): "a single connection shared between windows and across window reloads … reduces the number of times a password needs to be entered". VS Code suggests setting it to false when auth prompts misbehave [V1].
  - `remote.SSH.remoteServerListenOnSocket` (default false): the server "will listen on a socket path instead of opening a port … Disables the 'local server' connection multiplexing mode. Requires `AllowStreamLocalForwarding`".
  - `remote.SSH.connectTimeout` (default 15 s). gmertes raises it to 300 s so that job-starting ProxyCommands can wait for the queue [P1].
  - `remote.SSH.reconnectionGraceTime`: time "to wait before terminating the remote server when the client disconnects".
  - `remote.SSH.showLoginTerminal`: reveals the login terminal so you can answer 2FA prompts [V1].
- **Does the server die with the job?**
  - With pam_slurm_adopt, yes: processes started via the adopted ssh session are killed at job end [SL1].
  - Without it (node reachable without a job), server processes may **outlive** the job. They are not in the job cgroup (*inference*).
  - Separately, the VS Code server keeps itself alive after the client disconnects. The default reconnection grace is **3 hours** (`ReconnectionGraceTime = 3 * 60 * 60 * 1000`; CLI flag `--reconnection-grace-time`, "Defaults to 10800") [V4][V5].
  - With `--enable-remote-auto-shutdown` it exits `SHUTDOWN_TIMEOUT = 5 min` after the last consumer disconnects [V5][V6]. Whether Remote-SSH passes this flag is closed source and **unverified**.
  - NERSC sets `remote.SSH.maxReconnectionAttempts: 2` so the client gives up when the allocation ends [P3].
  - Manual cleanup: the **Remote-SSH: Kill VS Code Server on Host** command, or `kill` plus removing `~/.vscode-server` [V1].
- **VS Code Remote Tunnels (`code tunnel`)** [V2 tunnels.md]:
  - How it works: run `code tunnel` on the node and log in with GitHub or Microsoft; traffic goes through Microsoft dev tunnels in Azure over outbound connections, with no inbound ports.
  - Limit: 10 registered tunnels per account; above that the CLI deletes a random unused one.
  - "an instance of the server is designed to be accessed by one user or client at a time".
  - FASRC (Harvard) recommends tunnel-via-sbatch for "resilience toward network glitches" [P4].
  - **Pros on HPC:** no ssh-to-node needed, no ssh config, survives laptop network changes.
  - **Cons:**
    - Needs outbound internet from compute nodes (**unverified** for GenomeDK).
    - Routes code and terminal traffic through a Microsoft relay. That is questionable for genomic data under GenomeDK's governance; ask GenomeDK support.
    - Adds a GitHub or Microsoft login inside the job.
    - Tunnel names need managing.
    - The license forbids hosting it as a service [V2 vscode-server.md]. That is fine for personal use.

---

## 5. Idle auto-termination

**What Slurm gives you:**
- `--time` is a hard wall. At the limit each task gets "SIGTERM followed by SIGKILL", separated by `KillWait` [SL2][SL3].
- `--signal=<sig>@<secs>` sends a warning before the end [SL2].
- Users can only **reduce** TimeLimit. "Only a privileged user can increase a running or suspended job's TimeLimit". The syntax is `scontrol update JobId=… TimeLimit-=…` [SL4].
- **`InactiveLimit` applies only to "a non-responsive job allocation command (e.g. srun or salloc)"** [SL3]. It does nothing for a `sbatch` job that runs `sleep`.

**Design implication:** request a generous `--time` and let the job end itself early. The job ends when its batch script exits, so the script *is* the watchdog.

**Idle detection options (run inside the job, on the node):**

1. **Count your own sshd sessions on the node.**
   - While a VS Code window is connected, an ssh connection from the login node to this node is open. The per-user sshd child has a process title like `sshd: user@notty`; newer OpenSSH uses `sshd-session` [S3].
   - Loop: `pgrep -u $USER -f 'sshd(-session)?: '"$USER"`. If zero for N consecutive minutes, and a startup grace period has passed, `exit 0`.
   - Caveat: a local `ControlPersist` on the *node* hop keeps the session alive after the window closes. That is fine, since it only adds the ControlPersist time.
2. **Check VS Code server processes** (`pgrep -f .vscode-server`). **Not reliable** on its own: the server lingers for the 3 h reconnection grace after the client leaves [V4][V5]. Useful as a secondary signal only.
3. **Check established TCP connections to :22** (`ss -tn state established '( sport = :22 )'`). This cannot tell users apart without root. Weaker than option 1.
4. **Tie the job to the connection (salloc in ProxyCommand).**
   - FASRC's pattern: `ProxyCommand ssh cluster "salloc … /bin/bash -c 'nc $SLURM_NODELIST 22'"` [P4]. The allocation lives exactly as long as the proxy connection.
   - Pair it with local `ControlMaster` + `ControlPersist 10m` so VS Code's two connections share one allocation [V1]. The job then ends about 10 min after the last window closes.
   - This is the only option where Slurm's own `InactiveLimit` helps [SL3].
   - Downsides:
     - A laptop network blip or sleep kills the job.
     - Queue waits happen inside VS Code's connect timeout.
     - You get no menu-bar-visible "job running before I open VS Code" state.
5. **Local-side reaper:** the menu bar app cancels jobs it has not seen connected for N minutes. This fails when the laptop is asleep or offline, so it should back up option 1, not replace it.

*Recommendation (inference):* sbatch a script that sleeps in a loop and exits after N idle minutes using option 1, add `--signal` for a warning, and have the app show time left from `squeue %L` [SL5].

---

## 6. macOS menu bar app options

| Option | Effort | ssh in background | Distribution to colleague | Notes |
|---|---|---|---|---|
| **SwiftUI `MenuBarExtra`** | Medium (Swift/Xcode) | `Foundation.Process` runs `/usr/bin/ssh` [A3] | Needs Developer ID + notarization for a clean Gatekeeper pass [A4]. Otherwise ad hoc signing, and the colleague uses "Open Anyway" in Privacy & Security [A5] or builds from source | "A scene that renders itself as a persistent control in the system menu bar", **macOS 13+** [A1]. `.window` style gives a popover for settings [A1b]. Launch-at-login via `SMAppService` (13+) [A6]. |
| **AppKit `NSStatusItem`** | Medium–high | Same | Same | "An individual element displayed in the system menu bar"; all macOS versions [A2]. More control, more code. |
| **SwiftBar plugin** | **Low** (one shell script) | The script *is* shell. Menu items run `bash=…` with `terminal=false`, `refresh=true` [M1] | Colleague installs SwiftBar (`brew install swiftbar`, MIT, macOS 12+) and drops in the script. No signing needed for the script | Filename sets the refresh rate, e.g. `gimlet.30s.sh`. Output before `---` is the title. Streamable plugins exist [M1]. Active: v2.1.1, 2026-08-11 [M1r]. Settings UI is limited (env vars or a config file). |
| **xbar** | Low | Same model | `bash=`, `terminal=false` [M2] | Last release v2.1.7-**beta**, 2021-10-29 [M2r]. Effectively unmaintained, so prefer SwiftBar. |
| **rumps (Python)** | Low–medium | `subprocess` | py2app bundle with `LSUIElement` [M3]; same signing issues as Swift, plus Python packaging | Last PyPI release 0.4.0, 2022-10-15 [M3r]. |
| **Hammerspoon** | Low (Lua) | `hs.task` | Colleague installs Hammerspoon and adds the config | `hs.menubar.new()`, `setTitle`, `setMenu` with `fn` callbacks [M4]. Latest 1.1.1, 2026-02-26 [M4r]. Heavyweight dependency for one menu. |

- **Signing facts:**
  - Since macOS 10.15, all software built after June 1, 2019 and distributed with Developer ID must be notarized [A4].
  - Notarization needs a paid Apple Developer account (*inference* from Developer ID requirement).
  - For two users, an **unsigned or ad hoc build from source** (as SlurmBar does [P6]) or a **SwiftBar script** avoids that cost.
- **Auth in a GUI app:**
  - Background ssh should use `BatchMode=yes` [S1] and never prompt.
  - SlurmBar's pattern: the user opens a ControlMaster in Terminal (doing 2FA there), and the app joins the socket; it "never asks for your password" [P6].
  - GenomeDK's documented key has no passphrase [G1], so key auth alone likely works (§2 caveat).

---

## 7. Prior art

- **gmertes/vscode-remote-hpc** [P1] (commit `93a06b2`, 2026-06-10). A local `Host vscode-remote-cpu` with `ProxyCommand ssh HPC-LOGIN "~/bin/vscode-remote cpu"`. The remote script finds or starts a job (`sbatch -J vscode-remote%PORT`), which runs a **user-mode `sshd -D -p PORT`** with its own host key, then connects with `nc node port`. Jobs are reused across windows. There is no idle kill ("Jobs are expected to be automatically killed … wall clock time"). It sets `remote.SSH.connectTimeout: 300`.
- **AAU BioCloud "sshdslurm"** [P2] (Aalborg University). The same idea: sshd in the job plus `ProxyCommand ssh login "nc $(squeue --me --name=sshdbridge --states=R -h -O NodeList,Comment)"`. Jobs must be `scancel`led manually.
- **NERSC** [P3]. `Host nid??????` + `ProxyJump perlmutter.nersc.gov` + `Hostname %h` (the node-name-as-alias pattern, like the colleague's). VS Code settings `maxReconnectionAttempts: 2` and `useFlock: false`.
- **Harvard FASRC** [P4]. Two options:
  - Remote-SSH with a `ProxyCommand` that runs `salloc … nc $SLURM_NODELIST 22`, which ties the job to the connection.
  - `code tunnel` in an sbatch job, which they recommend.
  
  They also cap users at 5 login sessions.
- **Open OnDemand `bc_osc_codeserver`** [P5]. Web code-server in a batch job via the OOD portal. It is site-installed; GenomeDK does not appear to offer OOD (the desktop is their own "GenomeDK Desktop" [G1]).
- **Other site guides** found in search, not analysed: Caltech, NIH Biowulf, KIT HoreKa, Princeton, Oregon State, UF.
- **Menu bar Slurm apps (monitor only, none start or kill VS Code jobs):**
  - **SlurmBar** [P6]: SwiftUI, macOS 14+, joins a user-opened ControlMaster, `BatchMode=yes`, ad hoc signed, MIT.
  - **Orbit** [P7]: Swift, macOS 13+, `/usr/bin/ssh` with `BatchMode=yes`, SQLite, Sparkle.
  - **plgrid-queue-macos** [P8]: SwiftUI `MenuBarExtra`, macOS 13+.
  
  → The monitoring half is proven. The "start / attach / auto-stop VS Code job" half appears to be new.

---

## 8. Risks and open issues

1. **Alias naming with several jobs.** Node-name aliases (B) collide when jobs share a node. Job-ID aliases (A/C) are unique, but pam_slurm_adopt may still adopt the session into the "newest" job [SL1].
2. **Stale ssh config.** Design A leaves dead entries if the app is not running when a job ends. Design C or B avoids config rewriting entirely. Never edit `~/.ssh/config` beyond one `Include` line [S1].
3. **Host keys.**
   - Both existing tools use `StrictHostKeyChecking no`.
   - Prefer `accept-new`, or collect node keys once. `HostKeyAlias` is needed for ProxyCommand aliases [S1].
4. **Auth prompts in a GUI app.** 2FA behaviour with keys is unverified (§2). Use `BatchMode=yes` plus a ControlMaster, and surface "please log in in Terminal" instead of prompting [P6].
5. **Network.** VPN requirement and laptop sleep/wake behaviour are unknown. VS Code reconnects, and ControlMaster sockets can go stale; `ssh -O check` helps [S2].
6. **Queue waits.** A job can pend for a long time. The app should show PENDING with `squeue %R` and `--start` estimates [SL5]. If VS Code starts the job itself (ProxyCommand designs), `connectTimeout` must cover the wait [V3][P1].
7. **Server lifetime.** The VS Code server lingers for up to 3 h [V4] and may survive the job without pam_slurm_adopt, creating zombie processes on nodes.
8. **Watchdog false positives and negatives.** A local ControlPersist on the node hop delays the idle signal. The sshd process title differs across OpenSSH versions [S3].
9. **Shared `~/.vscode-server` on NFS.** Locking issues are possible; the fixes are `lockfilesInTmp` or `useFlock:false` [V3][P3].
10. **Compute-node internet.** The VS Code server downloads extensions on the remote host [V1]. If nodes are offline, install once from the login node (shared home) or use `localServerDownload` [V3].
11. **Policy.** GenomeDK has no published stance on long idle "holder" jobs or on ssh to nodes. Ask support before sharing the tool more widely.

---

## Feasibility summary

- **Feasible, and mostly glue.** Every building block is documented:
  - sbatch, squeue, scancel, `--signal` [SL2][SL5]
  - ssh `Include`, ProxyJump/ProxyCommand, ControlMaster [S1]
  - `code --remote ssh-remote+HOST` [V1]
  - MenuBarExtra or SwiftBar [A1][M1]
- The one missing piece in both existing tools is **auto-termination**. A self-exiting batch script that counts the user's sshd sessions on its node solves it without admin help [SL3][S3].
- **Lowest-effort path (inference):**
  1. Static `Include`d config with `Host gimlet-*` + `ProxyCommand` helper (Design C), or `Host cn-* gn-*` (Design B).
  2. A ControlMaster to the login node.
  3. A watchdog job script.
  4. A **SwiftBar** plugin for the menu. Nothing to sign, and the colleague installs SwiftBar with brew.
- **Step up later:** a SwiftUI `MenuBarExtra` app (macOS 13+) for a real settings window. Share it as a source build or ad hoc build unless someone pays for Developer ID notarization.
- **`code tunnel`** is a viable fallback if ssh to nodes is blocked, but it has data-governance and internet-access questions.

## Open questions for the user

1. From the login node, does `ssh cn-XXXX` to a node where you have **no** job get refused? If so, GenomeDK uses pam_slurm_adopt.
2. Does key-based login to `login.genome.au.dk` skip the 2FA code? (Your script suggests yes.)
3. Off campus, can you reach `login.genome.au.dk` without the AU VPN?
4. Do compute nodes have outbound internet? (`curl -I https://update.code.visualstudio.com` inside a job.)
5. Which idle timeout, and what default resources (account, partition, time, cpus, mem)?
6. Is SwiftBar acceptable as a dependency for you and your colleague, or must it be a standalone `.app`?
7. One job per VS Code window (colleague's model) or one shared job (yours), or both?
8. Should the app open VS Code itself (`code --remote …`, and to which folder), or only keep hosts available?

---

## Sources

Local / source code:
- [L1] `/Users/au468644/vscode_ssh/genomeDK.config` (read 2026-09-30)
- [L2] `/Users/au468644/vscode_ssh/setup_custom_config.sh` (read 2026-09-30)
- [L3] `~/.ssh/config`, the first 8 lines (Include, `Host *`, `Host GenomeDK`). Key paths were not recorded.
- [C1] https://github.com/micknudsen/vscode-hpc/blob/cfd6af81e48bc5feebc161a764dba981497f1e9a/README.md
- [C2] https://github.com/micknudsen/vscode-hpc/blob/cfd6af81e48bc5feebc161a764dba981497f1e9a/vscode-hpc (line refs as `L…`)

GenomeDK (accessed 2026-09-30):
- [G1] https://genome.au.dk/docs/getting-started/
- [G2] https://genome.au.dk/docs/
- [G3] https://genome.au.dk/docs/interacting-with-the-queue/
- [G4] https://genome.au.dk/docs/software-specific/ (Jupyter section)
- [G5] https://genome.au.dk/docs/projects-and-accounting/
- [G6] https://genome.au.dk/news/newsletter-july-2024/
- [G7] https://genome.au.dk/news/newsletter-january-2025/
- [G8] https://genome.au.dk/docs/partitions-and-resource-limits/
- [G9] https://genome.au.dk/docs/hardware/

OpenSSH:
- [S0] `ssh -V` on this Mac: `OpenSSH_10.3p1, LibreSSL 3.3.6`
- [S1] `ssh_config(5)`: local `man ssh_config`, and https://man.openbsd.org/ssh_config
- [S2] `ssh(1)`: local `man ssh`, and https://man.openbsd.org/ssh (`-O`, `-W`)
- [S3] OpenSSH release notes, `sshd-session` process title: https://www.openssh.com/releasenotes.html

VS Code:
- [V1] https://github.com/microsoft/vscode-docs/blob/8889b0542cb2144fb53f5f53bd19c1395e2d9fa1/docs/remote/troubleshooting.md and `docs/remote/ssh.md` (= https://code.visualstudio.com/docs/remote/troubleshooting, …/ssh)
- [V2] same commit: `docs/remote/tunnels.md`, `docs/remote/faq.md`, `docs/remote/vscode-server.md` (= https://code.visualstudio.com/docs/remote/tunnels)
- [V3] Remote-SSH extension v0.124.0 `package.json` + `package.nls.json` (setting descriptions), from `~/.vscode/extensions/ms-vscode-remote.remote-ssh-0.124.0/`
- [V4] https://github.com/microsoft/vscode/blob/c46161fa184b32f37c459cb7eaf64200ecc874ff/src/vs/base/parts/ipc/common/ipc.net.ts (`ReconnectionGraceTime`)
- [V5] https://github.com/microsoft/vscode/blob/c46161fa184b32f37c459cb7eaf64200ecc874ff/src/vs/server/node/serverEnvironmentService.ts (`reconnection-grace-time`, `enable-remote-auto-shutdown`)
- [V6] https://github.com/microsoft/vscode/blob/c46161fa184b32f37c459cb7eaf64200ecc874ff/src/vs/server/node/serverLifetimeService.ts (`SHUTDOWN_TIMEOUT = 5 min`, auto-shutdown off by default)

Slurm:
- [SL1] https://slurm.schedmd.com/pam_slurm_adopt.html
- [SL2] https://slurm.schedmd.com/sbatch.html (`--time`, `--signal`, `--parsable`)
- [SL3] https://slurm.schedmd.com/slurm.conf.html (`InactiveLimit`, `KillWait`)
- [SL4] https://slurm.schedmd.com/scontrol.html (TimeLimit update rules)
- [SL5] https://slurm.schedmd.com/squeue.html (`--me`, `%L`, `%R`, `--start`)

Apple:
- [A1] https://developer.apple.com/documentation/swiftui/menubarextra (macOS 13.0)
- [A1b] https://developer.apple.com/documentation/swiftui/menubarextrastyle/window
- [A2] https://developer.apple.com/documentation/appkit/nsstatusitem
- [A3] https://developer.apple.com/documentation/foundation/process
- [A4] https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- [A5] https://support.apple.com/en-us/102445
- [A6] https://developer.apple.com/documentation/servicemanagement/smappservice

Menu bar tools:
- [M1] https://github.com/swiftbar/SwiftBar
- [M1r] latest release v2.1.1, 2026-08-11 (GitHub API)
- [M2] https://github.com/matryer/xbar
- [M2r] latest release v2.1.7-beta, 2021-10-29 (GitHub API)
- [M3] https://github.com/jaredks/rumps
- [M3r] PyPI rumps 0.4.0, 2022-10-15
- [M4] https://www.hammerspoon.org/docs/hs.menubar.html
- [M4r] Hammerspoon 1.1.1, 2026-02-26 (GitHub API)

Prior art:
- [P1] https://github.com/gmertes/vscode-remote-hpc (commit 93a06b2, `README.md`, `vscode-remote-job.sh`, `vscode-remote.sh`)
- [P2] https://cmc-aau.github.io/biocloud-docs/guides/sshdslurm/
- [P3] https://docs.nersc.gov/connect/vscode/
- [P4] https://docs.rc.fas.harvard.edu/kb/vscode-remote-development-via-ssh-or-tunnel/
- [P5] https://github.com/OSC/bc_osc_codeserver
- [P6] https://github.com/yuchengwang-stat/slurmbar
- [P7] https://github.com/nikitakavka/orbit
- [P8] https://github.com/mpiorczynski/plgrid-queue-macos
