"""Run with python3 test_mount_retry.py; no SSH connections or mounts are opened."""

import os
from pathlib import Path
import re
import subprocess
import tempfile


source = Path(__file__).with_name("gimlet").read_text()
mount_home = re.search(r"^mount_home\(\) \{\n.*?^\}", source, re.M | re.S).group()

with tempfile.TemporaryDirectory(prefix="gimlet-mount-retry-") as directory:
    root = Path(directory)
    calls = root / "calls"
    setup = '''SSH_CONFIG=test-config
USERNAME=test-user
mounted() { return 1; }
logged_in() { echo 'unexpected login attempt' >&2; exit 99; }
ssh() {
    echo check >> "$CALLS"
    [ "$*" = '-F test-config -O check gimlet-login' ] || exit 99
    [ "$LOGIN" != no ] || return 1
    [ "$LOGIN" != drops ] || [ ! -f "$ATTEMPTED" ]
}
sshfs() {
    echo sshfs >> "$CALLS"
    if [ "$OUTCOME" = fail ] || { [ "$OUTCOME" = retry ] && [ ! -f "$ATTEMPTED" ]; }; then
        touch "$ATTEMPTED"
        echo 'mount failed' >&2
        return 1
    fi
}
die() { echo "$*" >&2; exit 1; }
recover_mount() { return 0; }
open() { :; }
refresh() { :; }
'''
    for login, outcome, expected_calls, error in (
        ("no", "success", "check\n", "not logged in"),
        ("yes", "success", "check\nsshfs\n", ""),
        ("yes", "retry", "check\nsshfs\ncheck\nsshfs\n", ""),
        ("yes", "fail", "check\nsshfs\ncheck\nsshfs\n", "could not mount GenomeDK: mount failed"),
        ("drops", "fail", "check\nsshfs\ncheck\n", "not logged in"),
    ):
        calls.write_text("")
        (root / "attempted").unlink(missing_ok=True)
        env = dict(os.environ, CALLS=str(calls), ATTEMPTED=str(root / "attempted"),
                   MOUNT=str(root / "mount"), LOGIN=login, OUTCOME=outcome)
        result = subprocess.run(
            ["bash", "-u", "-o", "pipefail", "-c", setup + mount_home + "\nmount_home"],
            env=env, text=True, capture_output=True, timeout=5,
        )
        assert result.returncode == (1 if error else 0), result
        assert error in result.stderr if error else not result.stderr, result
        assert calls.read_text() == expected_calls, calls.read_text()

print("Mount retry checks passed: existing login required, one retry, and login loss.")
