# Adds "Open in Code" to the right-click menu of GNOME Files (Nautilus).
#
# Installed by install.sh into ~/.local/share/nautilus-python/extensions/.
# Runs inside Nautilus through the nautilus-python bindings, using the
# system Python. It has no other dependencies.
import os
import shutil
import subprocess

from gi.repository import GObject, Nautilus

# The launcher installed by install.sh puts /usr/bin first on PATH so that
# Nautilus's embedded Python finds the system Python (see README, "The PATH
# fix"). Python has started by the time this file is imported, so put the
# original PATH back. Apps launched from Files then see the normal environment.
if "NAUTILUS_OPEN_IN_CODE_ORIG_PATH" in os.environ:
    os.environ["PATH"] = os.environ.pop("NAUTILUS_OPEN_IN_CODE_ORIG_PATH")

# Checked in order. OPEN_IN_CODE_EDITOR overrides all of them.
EDITOR_COMMANDS = ["code", "code-insiders", "codium"]
EDITOR_FALLBACK_PATHS = [
    "/usr/bin/code",
    "/snap/bin/code",
    "/usr/bin/code-insiders",
    "/snap/bin/code-insiders",
    "/usr/bin/codium",
    "/snap/bin/codium",
    "/var/lib/flatpak/exports/bin/com.visualstudio.code",
    os.path.expanduser("~/.local/share/flatpak/exports/bin/com.visualstudio.code"),
    "/var/lib/flatpak/exports/bin/com.vscodium.codium",
    os.path.expanduser("~/.local/share/flatpak/exports/bin/com.vscodium.codium"),
]


def find_editor():
    """Return the full path of the editor to launch, or None."""
    override = os.environ.get("OPEN_IN_CODE_EDITOR")
    if override:
        return shutil.which(override)
    for command in EDITOR_COMMANDS:
        found = shutil.which(command)
        if found:
            return found
    for path in EDITOR_FALLBACK_PATHS:
        if os.access(path, os.X_OK):
            return path
    return None


def local_paths(files):
    """Local filesystem paths of the given Nautilus files, without duplicates.

    Places that have no local path (Trash, Recent, Network, ...) are skipped.
    """
    paths = []
    for file in files:
        location = file.get_location()
        path = location.get_path() if location else None
        if path and path not in paths:
            paths.append(path)
    return paths


class OpenInCodeExtension(GObject.GObject, Nautilus.MenuProvider):
    def _launch(self, _menu, editor, paths):
        # start_new_session: the editor must not be tied to the Nautilus process.
        subprocess.Popen(
            [editor, *paths],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

    def _items(self, name, files):
        editor = find_editor()
        paths = local_paths(files)
        if not editor or not paths:
            return []
        item = Nautilus.MenuItem(
            name=name,
            label="Open in Code",
            tip="Open in Visual Studio Code",
        )
        item.connect("activate", self._launch, editor, paths)
        return [item]

    # nautilus-python 4 (Nautilus 43 and later) calls these with (files) and
    # (folder). Older versions pass a window first. Taking the last argument
    # works with both.

    # Right-click on selected files or folders.
    def get_file_items(self, *args):
        return self._items("OpenInCode::files", args[-1])

    # Right-click on the empty space inside a folder.
    def get_background_items(self, *args):
        return self._items("OpenInCode::background", [args[-1]])
