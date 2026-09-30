#!/bin/bash
# gimlet job: holds a compute node for VS Code and ends itself after
# the idle limit (IDLE_MINUTES in settings) without any ssh connection from you to this node.
# gimlet submits it by piping it into sbatch; nothing is installed on GenomeDK.

status=~/.gimlet/$SLURM_JOB_ID.status
trap 'rm -f "$status"' EXIT
trap 'exit' TERM

# Old logs, and status files left behind by jobs that were killed hard.
find ~/.gimlet -name '*.log' -mtime +7 -delete 2>/dev/null
find ~/.gimlet -name '*.status' -mtime +1 -delete 2>/dev/null

idle=0
while true; do
    # The menu keeps this file in line with your settings; IDLE_MINUTES is the value at submit time.
    limit=$(cat ~/.gimlet/idle_minutes 2>/dev/null || echo "${IDLE_MINUTES:-60}")
    # Every ssh connection to this node has a process owned by you, named
    # "sshd: you@..." (or "sshd-session: you@..." in newer OpenSSH).
    if pgrep -u "$USER" -f '^sshd(-session)?: ' > /dev/null; then
        idle=0
        echo "$SLURM_JOB_ID connected" > "$status"
    else
        [ "$idle" -ge "$limit" ] && break
        echo "$SLURM_JOB_ID idle $idle" > "$status"
        idle=$((idle + 1))
    fi
    sleep 60 &
    wait $!
done
echo "No ssh connection for $idle minutes, ending job."
