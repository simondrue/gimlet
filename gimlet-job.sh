#!/bin/bash
# gimlet job: holds a compute node for VS Code and ends itself after
# IDLE_MINUTES without any ssh connection from you to this node.
# gimlet submits it by piping it into sbatch.

# The menu reads ~/.gimlet/<jobid>: "connected" or "idle <minutes>".
# It is only written when the text changes, and removed when the job ends.
status=~/.gimlet/$SLURM_JOB_ID
report() {
    [ "$1" = "$reported" ] && return
    echo "$1" > "$status"
    reported=$1
}

trap 'rm -f "$status"' EXIT
trap 'exit' TERM

idle=0
while true; do
    # Every ssh connection to this node has a process owned by you, named
    # "sshd: you@..." (or "sshd-session: you@..." in newer OpenSSH).
    if pgrep -u "$USER" -f '^sshd(-session)?: ' > /dev/null; then
        idle=0
        report connected
    else
        [ "$idle" -ge "${IDLE_MINUTES:-60}" ] && break
        report "idle $idle"
        idle=$((idle + 1))
    fi
    sleep 60 &
    wait $!
done
