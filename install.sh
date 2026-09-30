#!/bin/bash
# Sets up gimlet: SwiftBar, your settings, the ssh config include and the menu bar plugin.
# Safe to run again.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd -P)"
CONF_DIR="$HOME/.config/gimlet"
INCLUDE="Include $CONF_DIR/ssh_config"

mkdir -p "$CONF_DIR"

# SwiftBar, in ~/Applications so no admin password is needed
swiftbar=/Applications/SwiftBar.app
[ -d "$swiftbar" ] || swiftbar="$HOME/Applications/SwiftBar.app"
if [ ! -d "$swiftbar" ]; then
    command -v brew > /dev/null || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
    mkdir -p "$HOME/Applications"
    brew install --cask --appdir="$HOME/Applications" swiftbar
fi

# Settings
if [ ! -f "$CONF_DIR/settings" ]; then
    read -rp "GenomeDK username: " username
    read -rp "Slurm account (project): " account
    [[ $username =~ ^[A-Za-z0-9_.-]+$ && $account =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Both are needed. Use only letters, digits, '_', '.' and '-'."; exit 1; }
    sed -e "s/^USERNAME=.*/USERNAME=$username/" -e "s/^ACCOUNT=.*/ACCOUNT=$account/" \
        "$HERE/settings.example" > "$CONF_DIR/settings"
fi
"$HERE/gimlet" ssh-config

# ssh reads Include lines placed after a Host line as part of that host, so it goes at the top.
mkdir -p ~/.ssh
touch ~/.ssh/config
if ! grep -qxF "$INCLUDE" ~/.ssh/config; then
    cp ~/.ssh/config ~/.ssh/config.before-gimlet
    { echo "$INCLUDE"; echo; cat ~/.ssh/config.before-gimlet; } > ~/.ssh/config
    echo "Added '$INCLUDE' to the top of ~/.ssh/config (backup in ~/.ssh/config.before-gimlet)"
fi

# Menu bar plugin, in SwiftBar's plugin folder (set to ~/SwiftBar if SwiftBar has none yet)
plugins=$(defaults read com.ameba.SwiftBar PluginDirectory 2> /dev/null) || {
    plugins="$HOME/SwiftBar"
    defaults write com.ameba.SwiftBar PluginDirectory -string "$plugins"
}
plugins="${plugins/#\~/$HOME}"
mkdir -p "$plugins"
rm -f "$plugins"/gimlet.{15s,1m,5m}.sh  # older installs refreshed more often
cat > "$plugins/gimlet.2m.sh" <<EOF
#!/bin/bash
# <xbar.title>gimlet</xbar.title>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
exec "$HERE/gimlet" menu
EOF
chmod +x "$plugins/gimlet.2m.sh"
echo "Menu bar plugin written to $plugins/gimlet.2m.sh"

# Start SwiftBar now and at every login
osascript -e 'on run argv' -e 'tell application "System Events" to if not (exists login item "SwiftBar") then make login item at end with properties {path:(item 1 of argv), hidden:true}' -e 'end run' "$swiftbar" > /dev/null \
    || echo "Could not add SwiftBar to login items; turn on 'Launch at login' in SwiftBar's preferences."
open "$swiftbar"

# A first notification makes macOS ask whether SwiftBar may send notifications. SwiftBar needs a moment to load the plugin.
sleep 3
open -g "swiftbar://notify?plugin=gimlet&title=gimlet&subtitle=Installed%20%F0%9F%8D%B8&body=Notifications%20work."
echo "If macOS asks, allow notifications from SwiftBar; gimlet uses them to say when a job starts or ends."

echo "Done. Click the gimlet icon in the menu bar and choose 'Log in to GenomeDK…'."
