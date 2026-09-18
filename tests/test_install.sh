#!/usr/bin/env bash
# Tests install.sh and uninstall.sh inside a temporary data folder.
# Nothing in your real home folder is touched, and Files is not restarted.
# Needs nautilus and nautilus-python to be installed already (no sudo is used).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
check() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "ok   - $description"
    else
        echo "FAIL - $description"
        failures=$((failures + 1))
    fi
}

run_install() { XDG_DATA_HOME="$1" DBUS_SESSION_BUS_ADDRESS="" "$REPO/install.sh" --no-restart "${@:2}" >/dev/null 2>&1; }
run_uninstall() { XDG_DATA_HOME="$1" DBUS_SESSION_BUS_ADDRESS="" "$REPO/uninstall.sh" >/dev/null 2>&1; }

# --- plain install
D="$TMP/plain"
run_install "$D"
check "extension is installed" test -f "$D/nautilus-python/extensions/open-in-code.py"
check "launcher is executable" test -x "$D/nautilus-open-in-code/nautilus-launcher"
check "launcher starts the real nautilus" grep -q 'exec "/usr/bin/nautilus"' "$D/nautilus-open-in-code/nautilus-launcher"
check "launcher puts /usr/bin first" grep -q 'PATH="/usr/bin:\$PATH"' "$D/nautilus-open-in-code/nautilus-launcher"
check "Nautilus service override points at launcher" \
    grep -q "^Exec=$D/nautilus-open-in-code/nautilus-launcher --gapplication-service$" "$D/dbus-1/services/org.gnome.Nautilus.service"
check "FileManager1 service override exists" test -f "$D/dbus-1/services/org.freedesktop.FileManager1.service"

# --- the launcher really changes PATH and keeps the original
cat >"$TMP/fake-nautilus" <<'EOF'
#!/bin/sh
echo "PATH=$PATH"
echo "ORIG=$NAUTILUS_OPEN_IN_CODE_ORIG_PATH"
echo "ARGS=$*"
EOF
chmod +x "$TMP/fake-nautilus"
sed "s|exec \"/usr/bin/nautilus\"|exec \"$TMP/fake-nautilus\"|" "$D/nautilus-open-in-code/nautilus-launcher" >"$TMP/launcher-under-test"
chmod +x "$TMP/launcher-under-test"
out="$(PATH="/home/u/.local/bin:/usr/bin:/bin" "$TMP/launcher-under-test" --new-window "/a b")"
check "launcher: system Python dir comes first" grep -q '^PATH=/usr/bin:/home/u/.local/bin:/usr/bin:/bin$' <<<"$out"
check "launcher: original PATH is kept for restoring" grep -q '^ORIG=/home/u/.local/bin:/usr/bin:/bin$' <<<"$out"
check "launcher: arguments are passed through" grep -q '^ARGS=--new-window /a b$' <<<"$out"

# --- running it twice is fine
run_install "$D"
check "second run still works" test -x "$D/nautilus-open-in-code/nautilus-launcher"

# --- uninstall
run_uninstall "$D"
check "uninstall removes the extension" test ! -e "$D/nautilus-python/extensions/open-in-code.py"
check "uninstall removes the launcher" test ! -e "$D/nautilus-open-in-code"
check "uninstall removes the service overrides" test ! -e "$D/dbus-1/services/org.gnome.Nautilus.service"

# --- --no-path-fix
D="$TMP/nofix"
run_install "$D" --no-path-fix
check "--no-path-fix: extension is installed" test -f "$D/nautilus-python/extensions/open-in-code.py"
check "--no-path-fix: no launcher" test ! -e "$D/nautilus-open-in-code"
check "--no-path-fix: no service overrides" test ! -e "$D/dbus-1/services/org.gnome.Nautilus.service"

# --- somebody else's service override is left alone, by install and uninstall
D="$TMP/foreign"
mkdir -p "$D/dbus-1/services"
printf '[D-BUS Service]\nName=org.gnome.Nautilus\nExec=/opt/custom\n' >"$D/dbus-1/services/org.gnome.Nautilus.service"
run_install "$D"
check "foreign override survives install" grep -q '^Exec=/opt/custom$' "$D/dbus-1/services/org.gnome.Nautilus.service"
run_uninstall "$D"
check "foreign override survives uninstall" grep -q '^Exec=/opt/custom$' "$D/dbus-1/services/org.gnome.Nautilus.service"

# --- a data folder with spaces in its name
D="$TMP/with space"
run_install "$D"
check "spaces: extension is installed" test -f "$D/nautilus-python/extensions/open-in-code.py"
check "spaces: launcher path is quoted in the service file" \
    grep -qF "Exec=\"$D/nautilus-open-in-code/nautilus-launcher\" --gapplication-service" "$D/dbus-1/services/org.gnome.Nautilus.service"

# --- bad option
if "$REPO/install.sh" --bogus >/dev/null 2>&1; then
    echo "FAIL - unknown option is rejected"
    failures=$((failures + 1))
else
    echo "ok   - unknown option is rejected"
fi

echo
if [ "$failures" -eq 0 ]; then
    echo "All installer tests passed."
else
    echo "$failures installer test(s) failed."
    exit 1
fi
