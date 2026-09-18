"""Tests for open-in-code.py.

Run with the system Python, which has the gi and Nautilus bindings:

    /usr/bin/python3 -m unittest discover -s tests -v
"""
import importlib.util
import os
import unittest
from pathlib import Path
from unittest import mock

EXTENSION = Path(__file__).resolve().parent.parent / "open-in-code.py"


def load_extension():
    spec = importlib.util.spec_from_file_location("open_in_code", EXTENSION)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FakeLocation:
    def __init__(self, path):
        self._path = path

    def get_path(self):
        return self._path


class FakeFile:
    """Stands in for a Nautilus.FileInfo."""

    def __init__(self, path, has_location=True):
        self._location = FakeLocation(path) if has_location else None

    def get_location(self):
        return self._location


class PathRestoreTest(unittest.TestCase):
    def test_original_path_is_restored_on_import(self):
        env = {"PATH": "/usr/bin:/home/u/.local/bin", "NAUTILUS_OPEN_IN_CODE_ORIG_PATH": "/home/u/.local/bin:/usr/bin"}
        with mock.patch.dict(os.environ, env, clear=True):
            load_extension()
            self.assertEqual(os.environ["PATH"], "/home/u/.local/bin:/usr/bin")
            self.assertNotIn("NAUTILUS_OPEN_IN_CODE_ORIG_PATH", os.environ)

    def test_path_untouched_without_launcher(self):
        with mock.patch.dict(os.environ, {"PATH": "/a:/b"}, clear=True):
            load_extension()
            self.assertEqual(os.environ["PATH"], "/a:/b")


class LocalPathsTest(unittest.TestCase):
    def setUp(self):
        self.ext = load_extension()

    def test_spaces_and_unicode_are_kept(self):
        files = [FakeFile("/home/u/My Project"), FakeFile("/home/u/café/ünï")]
        self.assertEqual(self.ext.local_paths(files), ["/home/u/My Project", "/home/u/café/ünï"])

    def test_places_without_a_local_path_are_skipped(self):
        # Trash, Recent, Network and similar places have no local path.
        files = [FakeFile(None), FakeFile("/x", has_location=False), FakeFile("/home/u/ok")]
        self.assertEqual(self.ext.local_paths(files), ["/home/u/ok"])

    def test_duplicates_are_removed(self):
        files = [FakeFile("/a"), FakeFile("/a"), FakeFile("/b")]
        self.assertEqual(self.ext.local_paths(files), ["/a", "/b"])


class FindEditorTest(unittest.TestCase):
    def setUp(self):
        self.ext = load_extension()

    def test_prefers_code_on_path(self):
        with mock.patch.object(self.ext.shutil, "which", side_effect=lambda c: f"/usr/bin/{c}"):
            self.assertEqual(self.ext.find_editor(), "/usr/bin/code")

    def test_falls_back_to_codium(self):
        which = lambda c: "/usr/bin/codium" if c == "codium" else None
        with mock.patch.object(self.ext.shutil, "which", side_effect=which):
            self.assertEqual(self.ext.find_editor(), "/usr/bin/codium")

    def test_falls_back_to_known_locations(self):
        with mock.patch.object(self.ext.shutil, "which", return_value=None), \
                mock.patch.object(self.ext.os, "access", side_effect=lambda p, _m: p == "/snap/bin/code"):
            self.assertEqual(self.ext.find_editor(), "/snap/bin/code")

    def test_none_when_nothing_is_installed(self):
        with mock.patch.object(self.ext.shutil, "which", return_value=None), \
                mock.patch.object(self.ext.os, "access", return_value=False):
            self.assertIsNone(self.ext.find_editor())

    def test_environment_override(self):
        with mock.patch.dict(os.environ, {"OPEN_IN_CODE_EDITOR": "my-editor"}), \
                mock.patch.object(self.ext.shutil, "which", side_effect=lambda c: f"/opt/{c}"):
            self.assertEqual(self.ext.find_editor(), "/opt/my-editor")


class MenuTest(unittest.TestCase):
    def setUp(self):
        self.ext = load_extension()
        self.provider = self.ext.OpenInCodeExtension()
        patcher = mock.patch.object(self.ext, "find_editor", return_value="/usr/bin/code")
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_background_item_new_api(self):
        items = self.provider.get_background_items(FakeFile("/home/u/proj"))
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0].props.label, "Open in Code")

    def test_old_api_with_window_argument(self):
        window = object()
        self.assertEqual(len(self.provider.get_background_items(window, FakeFile("/p"))), 1)
        self.assertEqual(len(self.provider.get_file_items(window, [FakeFile("/p")])), 1)

    def test_no_item_for_places_without_a_local_path(self):
        self.assertEqual(self.provider.get_background_items(FakeFile(None)), [])
        self.assertEqual(self.provider.get_file_items([FakeFile(None)]), [])

    def test_no_item_when_no_editor_is_installed(self):
        with mock.patch.object(self.ext, "find_editor", return_value=None):
            self.assertEqual(self.provider.get_background_items(FakeFile("/p")), [])

    def test_clicking_launches_editor_with_all_paths(self):
        files = [FakeFile("/home/u/My Project"), FakeFile("/home/u/notes.txt")]
        items = self.provider.get_file_items(files)
        with mock.patch.object(self.ext.subprocess, "Popen") as popen:
            items[0].emit("activate")
        args, kwargs = popen.call_args
        self.assertEqual(args[0], ["/usr/bin/code", "/home/u/My Project", "/home/u/notes.txt"])
        self.assertTrue(kwargs["start_new_session"])


if __name__ == "__main__":
    unittest.main()
