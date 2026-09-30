#!/bin/bash
# gimlet job: holds a compute node for VS Code and ends itself after
# IDLE_MINUTES without any ssh connection from you to this node.
# gimlet submits it by piping it into sbatch; nothing is stored on GenomeDK.

# The menu reads the job comment: "<preset> connected" or "<preset> idle <minutes>".
report() {
    [ "$1" = "$reported" ] && return
    scontrol update JobId="$SLURM_JOB_ID" Comment="$PRESET $1"
    reported=$1
}

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
