"""Run with python3 test_connection.py; SSH is mocked, no cluster login is opened."""

import os
from pathlib import Path
import re
import subprocess
import tempfile


source = Path(__file__).with_name("gimlet").read_text()
functions = "\n".join(
    re.search(r"^" + name + r"\(\) \{\n.*?^\}", source, re.M | re.S).group()
    for name in ("logged_in", "proxy", "menu")
)

with tempfile.TemporaryDirectory(prefix="gimlet-connection-") as directory:
    root = Path(directory)
    ssh = root / "ssh"
    ssh.write_text("""#!/bin/bash
printf '%s\\n' "$*" >> "$GIMLET_TEST_CALLS"
case " $* " in *" -n "*) exec < /dev/null ;; esac
case " $* " in
    *" -O check "*) exit "$GIMLET_TEST_CONNECTED" ;;
    *" -W "*) cat ;;
    *)
        if [ "$GIMLET_TEST_RECOVER" = 0 ]; then
            cat > /dev/null
            echo 'login banner'
            exit 0
        fi
        echo "$GIMLET_TEST_ERROR" >&2
        exit 255
        ;;
esac
""")
    ssh.chmod(0o700)
    calls = root / "calls"
    log = root / "connection.log"
    setup = '''CONF_DIR=$1
SELF=gimlet
SSH_CONFIG="$CONF_DIR/ssh_config"
SETTINGS="$CONF_DIR/settings"
JOB_FIELDS='{ name = $1; id = $2; state = $3; node = $4 }'
fetch() { echo 'gimlet-1|123|RUNNING|cn-test'; }
die() { echo "$*" >&2; exit 1; }
one_at_a_time() { :; }
red_menu() { printf '%s\\n' "$2"; }
'''

    def run(command, connected=1, recover=0, error="Permission denied"):
        calls.write_text("")
        env = dict(os.environ, PATH=directory + os.pathsep + os.environ["PATH"],
                   GIMLET_TEST_CALLS=str(calls), GIMLET_TEST_CONNECTED=str(connected),
                   GIMLET_TEST_RECOVER=str(recover), GIMLET_TEST_ERROR=error)
        return subprocess.run(
            ["bash", "-u", "-o", "pipefail", "-c", setup + functions + "\n" + command,
             "test", directory],
            input="SSH payload\n", text=True, capture_output=True, env=env, timeout=5,
        )

    result = run("logged_in", connected=0)
    assert result.returncode == 0 and not result.stdout and not result.stderr
    assert len(calls.read_text().splitlines()) == 1 and not log.exists()

    result = run("logged_in && cat")
    assert result.returncode == 0, result.stderr
    assert result.stdout == "SSH payload\n" and not result.stderr
    assert len(calls.read_text().splitlines()) == 2
    assert "reconnected" in log.read_text()
    attempt = calls.read_text().splitlines()[1]
    for option in ("-n", "BatchMode=yes", "ConnectTimeout=5", "ConnectionAttempts=1"):
        assert option in attempt, attempt

    for error in ("Permission denied", "Connection timed out"):
        result = run("logged_in", recover=1, error=error)
        assert result.returncode == 1 and not result.stdout and not result.stderr
        assert len(calls.read_text().splitlines()) == 2
        assert "reconnect failed: " + error in log.read_text()

    result = run("proxy gimlet-1")
    assert result.returncode == 0 and result.stdout == "SSH payload\n", result
    assert len(calls.read_text().splitlines()) == 3
    assert "-W cn-test:22" in calls.read_text()
    assert log.read_text().splitlines()[-1].endswith("reconnected")

    result = run("proxy gimlet-1", recover=1)
    assert result.returncode == 1 and not result.stdout
    assert "not logged in to GenomeDK" in result.stderr
    assert len(calls.read_text().splitlines()) == 2

    result = run("menu", recover=1)
    assert result.returncode == 0 and not result.stderr, result
    assert 'param1=login terminal=true' in result.stdout
    assert len(calls.read_text().splitlines()) == 2

print("Connection checks passed: reuse, recovery, failures, and proxy traffic.")
