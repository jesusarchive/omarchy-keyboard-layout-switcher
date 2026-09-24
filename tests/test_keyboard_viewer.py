"""Checks keyboard_viewer.py against libxkbcommon. Needs libxkbcommon and xkb-data."""

import ctypes.util
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import keyboard_viewer  # noqa: E402

SHIFT, CAPS, ALTGR = 1, 2, 4


@unittest.skipUnless(ctypes.util.find_library("xkbcommon"), "libxkbcommon is not installed")
class KeyboardViewerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.environ["LC_ALL"] = "en_US.UTF-8"
        cls.layouts = {}

    def layout(self, name, variant="", options=""):
        key = (name, variant, options)
        if key not in self.layouts:
            self.layouts[key] = keyboard_viewer.describe(name, variant, "", options)
        return self.layouts[key]

    def text(self, layout, key, state):
        entry = layout["keys"][key]["states"][state]
        return entry["text"] if entry else None

    def test_caps_lock_does_not_reach_altgr_symbols(self):
        es = self.layout("es")
        self.assertEqual(self.text(es, "AD03", CAPS), "E")
        self.assertEqual(self.text(es, "AD03", CAPS | ALTGR), "€")
        de = self.layout("de")
        self.assertEqual(self.text(de, "AD01", CAPS | ALTGR), "@")

    def test_shift_undoes_caps_lock_on_letters(self):
        self.assertEqual(self.text(self.layout("es"), "AD03", SHIFT | CAPS), "e")

    def test_altgr_comes_from_a_physical_key(self):
        self.assertEqual(self.layout("es")["altGrKey"], "RALT")
        self.assertEqual(self.layout("us")["altGrKey"], "")
        self.assertEqual(self.layout("us", "", "lv3:caps_switch")["altGrKey"], "CAPS")

    def test_dead_keys_are_marked_and_composed(self):
        es = self.layout("es")
        acute = es["keys"]["AC11"]["states"][0]
        self.assertEqual(acute["dead"], "dead_acute")
        self.assertEqual(acute["label"], "´")
        self.assertEqual(es["compose"]["dead_acute"]["e"], "é")
        self.assertEqual(es["compose"]["dead_acute"]["space"], "'")

    def test_accents_follow_the_macos_order(self):
        self.assertEqual(self.layout("es")["accents"]["e"][:4], ["è", "é", "ê", "ë"])

    def test_extra_keys_exist_only_where_the_layout_defines_them(self):
        self.assertEqual(self.text(self.layout("br"), "AB11", 0), "/")
        self.assertNotIn("AB11", self.layout("us")["keys"])


if __name__ == "__main__":
    unittest.main()
