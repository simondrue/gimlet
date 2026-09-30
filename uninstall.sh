#!/bin/bash
# Removes gimlet: the menu bar plugin, the ssh config include and ~/.config/gimlet.
# SwiftBar and any running jobs are left alone.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd -P)"
CONF_DIR="$HOME/.config/gimlet"
INCLUDE="Include $CONF_DIR/ssh_config"

if jobs=$("$HERE/gimlet" list 2> /dev/null) && [ -n "$jobs" ]; then
    echo "These jobs keep running until they go idle or you stop them with scancel:"
    echo "$jobs"
fi

# Menu bar plugin
plugins=$(defaults read com.ameba.SwiftBar PluginDirectory 2> /dev/null) || plugins="$HOME/SwiftBar"
rm -f "${plugins/#\~/$HOME}/gimlet.2m.sh"

# The Include line, and the blank line install.sh put after it
if grep -qxF "$INCLUDE" ~/.ssh/config 2> /dev/null; then
    cp ~/.ssh/config ~/.ssh/config.before-gimlet-uninstall
    awk -v inc="$INCLUDE" '$0 == inc { skip = 1; next } skip && $0 == "" { skip = 0; next } { skip = 0; print }' \
        ~/.ssh/config.before-gimlet-uninstall > ~/.ssh/config
    echo "Removed '$INCLUDE' from ~/.ssh/config (backup in ~/.ssh/config.before-gimlet-uninstall)"
fi

# The shared login connection, then settings and generated files
[ -f "$CONF_DIR/ssh_config" ] && ssh -F "$CONF_DIR/ssh_config" -O exit gimlet-login 2> /dev/null || true
rm -rf "$CONF_DIR"

echo "Done. SwiftBar is still installed; to remove it: brew uninstall --cask swiftbar, and remove it from Login Items."
