# nautilus-open-in-code

Adds an **Open in Code** entry to the right-click menu of GNOME Files (Nautilus), like the "Open with Code" entry that VS Code adds on Windows.

- Right-click the empty space inside a folder to open that folder in VS Code. This does the same as running `code .` there.
- Right-click selected files or folders to open them in VS Code.

## Install

```bash
git clone https://github.com/sharjeelmazhar/nautilus-open-in-code.git
cd nautilus-open-in-code
./install.sh
```

Then open Files and right-click a folder.

Run the script as your normal user. It asks for your password through `sudo` only when the `nautilus-python` package is missing and has to be installed. Everything else goes into your home folder.

Options:

| Option | What it does |
| --- | --- |
| `--no-path-fix` | Skips the launcher described in [The PATH fix](#the-path-fix). |
| `--no-restart` | Does not restart Files at the end. |

## Requirements

- GNOME Files (Nautilus). Tested with Nautilus 50 on Ubuntu 26.04.
- VS Code available as `code`. VS Code Insiders (`code-insiders`), VSCodium (`codium`), and the snap and flatpak builds are also found.
- The `nautilus-python` package. The installer installs it for you with `apt`, `dnf`, `pacman` or `zypper`.

You do not need to install Python, pip, uv or anything else. The extension runs inside Files on the system Python that comes with `nautilus-python`.

To use a different editor command, set `OPEN_IN_CODE_EDITOR` in your session environment, for example in `~/.config/environment.d/editor.conf`:

```
OPEN_IN_CODE_EDITOR=code-insiders
```

## Uninstall

```bash
./uninstall.sh
```

This removes everything the installer put in your home folder. The `nautilus-python` system package stays, because other Files extensions may use it.

## The PATH fix

On some systems the entry never shows up, even though the extension is installed correctly. The log (`journalctl --user -b | grep -i nautilus`) then contains:

```
ImportError: could not import gobject (error was: ModuleNotFoundError("No module named 'gi'"))
nautilus_python_init_python failed
```

This happens when another Python comes before the system Python on your `PATH`. Typical sources are `uv python install --default`, pyenv and conda. Files embeds the system Python, and that Python looks up `python3` on `PATH` to decide where its libraries are. If it finds the other Python, and that Python has the same minor version as the system one, Files loads that Python's libraries. Those do not include the `gi` module, so every Python extension for Files fails to load. This affects all nautilus-python extensions, not only this one.

The installer works around this without touching your other Python:

1. It installs a small launcher at `~/.local/share/nautilus-open-in-code/nautilus-launcher`. The launcher starts Files with `/usr/bin` first on `PATH`.
2. It adds per-user D-Bus service files in `~/.local/share/dbus-1/services/`, so Files is started through the launcher. These are generated from the system service files. A service file you created yourself is never overwritten.
3. When the extension loads, it puts the original `PATH` back. Programs you start from Files see your normal environment.

The fix is installed by default, because it is harmless when not needed and keeps the entry working if you install uv, pyenv or conda later. Skip it with `--no-path-fix`.

One limit: if Files is not running and you start it by typing `nautilus` in a terminal, the launcher is skipped. Starting Files from the dock, the app grid or another program goes through the launcher.

## Troubleshooting

**The entry does not appear.**
Log out and back in, or run `nautilus -q` and open Files again. Then check the log with `journalctl --user -b | grep -i nautilus`.

**The entry disappeared after I installed VS Code differently.**
The entry is hidden when no editor is found. Check that `code` runs in a terminal, then restart Files with `nautilus -q`.

**The entry is missing in Trash, Recent or Network.**
That is expected. These places are not real folders on disk, so there is nothing for VS Code to open. Mounted network shares work.

## Tests

```bash
/usr/bin/python3 -m unittest discover -s tests -v   # the extension
./tests/test_install.sh                             # the installer and uninstaller
```

The extension tests need the system Python, because only it has the `gi` module. The installer tests run inside a temporary folder and do not change your setup.

What has been tested: the full install, the PATH fix and the uninstall on Ubuntu 26.04 with Nautilus 50, the VS Code `.deb` package, and a uv-managed Python first on `PATH`. The `dnf`, `pacman` and `zypper` install commands and Nautilus versions before 43 are supported in the code but have not been run on real systems. Reports and fixes are welcome.

## License

MIT. See [LICENSE](LICENSE).
