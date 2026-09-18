#!/usr/bin/env bash
# Removes everything install.sh put in your home folder.
# The nautilus-python system package is left installed, because other Files
# extensions may need it.
set -euo pipefail

info() { printf '==> %s\n' "$*"; }

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
EXT_DIR="$DATA_HOME/nautilus-python/extensions"
FIX_DIR="$DATA_HOME/nautilus-open-in-code"
DBUS_DIR="$DATA_HOME/dbus-1/services"
MARKER="# Installed by nautilus-open-in-code"
SERVICES="org.gnome.Nautilus org.freedesktop.FileManager1"

info "Removing the extension"
rm -f "$EXT_DIR/open-in-code.py"
rm -f "$EXT_DIR/__pycache__"/open-in-code.*.pyc

info "Removing the PATH fix"
for name in $SERVICES; do
    target="$DBUS_DIR/$name.service"
    # Only remove service overrides that install.sh created.
    if [ -f "$target" ] && grep -qF "$MARKER" "$target"; then
        rm -f "$target"
    fi
done
rm -rf "$FIX_DIR"

if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    if command -v gdbus >/dev/null 2>&1; then
        gdbus call --session --dest org.freedesktop.DBus \
            --object-path /org/freedesktop/DBus \
            --method org.freedesktop.DBus.ReloadConfig >/dev/null 2>&1 || true
    fi
    info "Restarting Files (open Files windows will close)"
    nautilus -q >/dev/null 2>&1 || true
fi

info "Done. \"Open in Code\" has been removed."
