#!/bin/sh
# Only invoked by recovery SSH. A failed askpass alone sends an empty answer.
[ "${SSH_ASKPASS_REQUIRE:-}" = force ] || exit 1
echo 'gimlet: authentication needs input; use Log in to GenomeDK.' >&2
kill -TERM "$PPID"
exit 1
