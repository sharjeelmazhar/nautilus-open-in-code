#!/usr/bin/env bash
# Adds "Open in Code" to the right-click menu of GNOME Files (Nautilus).
# Everything is installed into your home folder. sudo is only used to install
# the nautilus-python system package when it is missing.
set -euo pipefail

PATH_FIX=1
RESTART=1

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]

  --no-path-fix   Do not install the launcher that makes Files use the system
                  Python (see "The PATH fix" in the README).
  --no-restart    Do not restart Files at the end.
  -h, --help      Show this help.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --no-path-fix) PATH_FIX=0 ;;
        --no-restart) RESTART=0 ;;
        -h | --help) usage; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

info() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
EXT_DIR="$DATA_HOME/nautilus-python/extensions"
FIX_DIR="$DATA_HOME/nautilus-open-in-code"
LAUNCHER="$FIX_DIR/nautilus-launcher"
DBUS_DIR="$DATA_HOME/dbus-1/services"
MARKER="# Installed by nautilus-open-in-code"
SERVICES="org.gnome.Nautilus org.freedesktop.FileManager1"

# ---------------------------------------------------------------- checks

[ "$(id -u)" -ne 0 ] || die "run this as your normal user, not as root or with sudo."
[ -f "$SCRIPT_DIR/open-in-code.py" ] || die "open-in-code.py not found next to install.sh."
command -v nautilus >/dev/null 2>&1 || die "GNOME Files (nautilus) is not installed."

editor_found=0
for candidate in code code-insiders codium /snap/bin/code \
    /var/lib/flatpak/exports/bin/com.visualstudio.code \
    "$DATA_HOME/flatpak/exports/bin/com.visualstudio.code"; do
    if command -v "$candidate" >/dev/null 2>&1; then
        editor_found=1
        break
    fi
done
[ "$editor_found" -eq 1 ] || warn "VS Code was not found. The menu entry stays hidden until it is installed."

# ---------------------------------------------------------------- nautilus-python

have_nautilus_python() {
    compgen -G "/usr/lib*/nautilus/extensions-*/libnautilus-python.so" >/dev/null ||
        compgen -G "/usr/lib/*/nautilus/extensions-*/libnautilus-python.so" >/dev/null
}

install_nautilus_python() {
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y python3-nautilus
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y nautilus-python
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm python-nautilus
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y python3-nautilus
    else
        die "could not find apt, dnf, pacman or zypper. Install the nautilus-python package for your distribution, then run this script again."
    fi
}

if have_nautilus_python; then
    info "nautilus-python is already installed."
else
    info "Installing nautilus-python (needs sudo)..."
    install_nautilus_python
    have_nautilus_python || die "nautilus-python still not found after installing it."
fi

# ---------------------------------------------------------------- extension

info "Installing the extension into $EXT_DIR"
mkdir -p "$EXT_DIR"
install -m 644 "$SCRIPT_DIR/open-in-code.py" "$EXT_DIR/open-in-code.py"

# ---------------------------------------------------------------- PATH fix

# Prints the path of the system D-Bus service file named $1.
system_service_file() {
    local name="$1" dir
    for dir in /usr/local/share/dbus-1/services /usr/share/dbus-1/services; do
        if [ -f "$dir/$name.service" ]; then
            echo "$dir/$name.service"
            return 0
        fi
    done
    return 1
}

# Files is started through D-Bus. Override its service files (per user) so that
# it starts through the launcher, which puts the system Python first on PATH.
install_path_fix() {
    local name sys_file exec_line binary rest target launcher_word nautilus_bin=""

    mkdir -p "$FIX_DIR" "$DBUS_DIR"

    for name in $SERVICES; do
        sys_file="$(system_service_file "$name")" || continue
        exec_line="$(grep -m1 '^Exec=' "$sys_file" || true)"
        exec_line="${exec_line#Exec=}"
        binary="${exec_line%% *}"
        rest=""
        [ "$binary" = "$exec_line" ] || rest="${exec_line#* }"

        # Only touch services that really start nautilus.
        [ "$(basename "$binary")" = "nautilus" ] || continue
        [ -n "$nautilus_bin" ] || nautilus_bin="$binary"

        target="$DBUS_DIR/$name.service"
        if [ -f "$target" ] && ! grep -qF "$MARKER" "$target"; then
            warn "$target already exists and was not created by this script. Leaving it alone."
            continue
        fi

        launcher_word="$LAUNCHER"
        case "$LAUNCHER" in *" "*) launcher_word="\"$LAUNCHER\"" ;; esac

        {
            echo "$MARKER"
            echo "[D-BUS Service]"
            echo "Name=$name"
            echo "Exec=$launcher_word${rest:+ $rest}"
        } >"$target"
    done

    if [ -z "$nautilus_bin" ]; then
        warn "no D-Bus service file for Files was found. Skipping the PATH fix."
        rm -rf "$FIX_DIR"
        return 0
    fi

    cat >"$LAUNCHER" <<EOF
#!/bin/sh
$MARKER
# Starts Files (Nautilus) with /usr/bin first on PATH, so that its embedded
# Python finds the system Python and not one from uv, pyenv, conda, etc.
# open-in-code.py restores the original PATH once Python has started.
export NAUTILUS_OPEN_IN_CODE_ORIG_PATH="\$PATH"
PATH="/usr/bin:\$PATH" exec "$nautilus_bin" "\$@"
EOF
    chmod 755 "$LAUNCHER"
}

reload_dbus() {
    [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || return 0
    command -v gdbus >/dev/null 2>&1 || return 0
    gdbus call --session --dest org.freedesktop.DBus \
        --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.ReloadConfig >/dev/null 2>&1 || true
}

if [ "$PATH_FIX" -eq 1 ]; then
    info "Installing the PATH fix (Files will use the system Python)"
    install_path_fix
    reload_dbus
else
    info "Skipping the PATH fix."
fi

# ---------------------------------------------------------------- restart

if [ "$RESTART" -eq 1 ] && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    info "Restarting Files (open Files windows will close)"
    nautilus -q >/dev/null 2>&1 || true
    for _ in $(seq 1 50); do
        pgrep -x nautilus >/dev/null 2>&1 || break
        sleep 0.1
    done
else
    info "Not restarting Files. Run 'nautilus -q' or log out and back in to finish."
fi

info "Done. Open Files and right-click a folder: you should see \"Open in Code\"."
