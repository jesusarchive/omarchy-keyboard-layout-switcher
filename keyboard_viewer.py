#!/usr/bin/env python3
"""Print one XKB layout as JSON for the keyboard viewer.

Each key lists what it produces in the viewer's eight states (Shift, Caps Lock
and AltGr, each on or off). libxkbcommon resolves every state, so key types
and Caps Lock rules match a physical keyboard. Dead keys come with the results
of the locale's Compose table, and letters come with their accented forms for
the press-and-hold popup.
"""

import ctypes
import ctypes.util
import json
import os
import sys
import unicodedata


KEYS = (
    "TLDE AE01 AE02 AE03 AE04 AE05 AE06 AE07 AE08 AE09 AE10 AE11 AE12 AE13 "
    "AD01 AD02 AD03 AD04 AD05 AD06 AD07 AD08 AD09 AD10 AD11 AD12 BKSL "
    "AC01 AC02 AC03 AC04 AC05 AC06 AC07 AC08 AC09 AC10 AC11 "
    "LSGT AB01 AB02 AB03 AB04 AB05 AB06 AB07 AB08 AB09 AB10 AB11"
).split()

# Labels for dead keys, which produce no text of their own.
DEAD_SYMBOLS = {
    "dead_acute": "´", "dead_grave": "`", "dead_circumflex": "^",
    "dead_tilde": "~", "dead_diaeresis": "¨", "dead_cedilla": "¸",
    "dead_caron": "ˇ", "dead_breve": "˘", "dead_abovering": "˚",
    "dead_macron": "¯", "dead_doubleacute": "˝", "dead_ogonek": "˛",
    "dead_abovedot": "˙", "dead_belowdot": "◌̣", "dead_hook": "◌̉",
    "dead_horn": "◌̛", "dead_stroke": "/", "dead_belowcomma": "◌̦",
    "dead_greek": "α", "dead_currency": "¤",
}

# Press-and-hold choices, in the order macOS lists them for "e": è é ê ë ē ė ę.
ACCENT_DEAD_KEYS = (
    "dead_grave", "dead_acute", "dead_circumflex", "dead_diaeresis",
    "dead_tilde", "dead_abovering", "dead_macron", "dead_abovedot",
    "dead_ogonek", "dead_cedilla", "dead_caron", "dead_breve",
    "dead_doubleacute", "dead_stroke",
)
EXTRA_ACCENTS = {"a": "æ", "A": "Æ", "o": "œø", "O": "ŒØ", "s": "ß"}
MAX_ACCENTS = 12

XKB_KEY_DOWN = 1
XKB_STATE_MODS_DEPRESSED = 1
XKB_COMPOSE_COMPOSED = 2


class RuleNames(ctypes.Structure):
    _fields_ = [(field, ctypes.c_char_p) for field in ("rules", "model", "layout", "variant", "options")]


def load_xkb():
    library = ctypes.util.find_library("xkbcommon")
    if not library:
        raise RuntimeError("libxkbcommon is unavailable")
    xkb = ctypes.CDLL(library)
    p, u32, i, c = ctypes.c_void_p, ctypes.c_uint32, ctypes.c_int, ctypes.c_char_p
    signatures = {
        "xkb_context_new": ([i], p),
        "xkb_context_unref": ([p], None),
        "xkb_keymap_new_from_names": ([p, ctypes.POINTER(RuleNames), i], p),
        "xkb_keymap_unref": ([p], None),
        "xkb_keymap_key_by_name": ([p, c], u32),
        "xkb_keymap_mod_get_index": ([p, c], u32),
        "xkb_keymap_key_get_syms_by_level": ([p, u32, u32, u32, ctypes.POINTER(ctypes.POINTER(u32))], i),
        "xkb_state_new": ([p], p),
        "xkb_state_unref": ([p], None),
        "xkb_state_update_key": ([p, u32, i], i),
        "xkb_state_update_mask": ([p, u32, u32, u32, u32, u32, u32], i),
        "xkb_state_serialize_mods": ([p, i], u32),
        "xkb_state_key_get_one_sym": ([p, u32], u32),
        "xkb_state_key_get_syms": ([p, u32, ctypes.POINTER(ctypes.POINTER(u32))], i),
        "xkb_keysym_to_utf32": ([u32], u32),
        "xkb_keysym_get_name": ([u32, c, ctypes.c_size_t], i),
        "xkb_keysym_from_name": ([c, i], u32),
        "xkb_compose_table_new_from_locale": ([p, c, i], p),
        "xkb_compose_table_unref": ([p], None),
        "xkb_compose_state_new": ([p, i], p),
        "xkb_compose_state_unref": ([p], None),
        "xkb_compose_state_reset": ([p], None),
        "xkb_compose_state_feed": ([p, u32], i),
        "xkb_compose_state_get_status": ([p], i),
        "xkb_compose_state_get_utf8": ([p, c, ctypes.c_size_t], i),
    }
    for name, (argtypes, restype) in signatures.items():
        function = getattr(xkb, name)
        function.argtypes = argtypes
        function.restype = restype
    return xkb


def keysym_name(xkb, keysym):
    buffer = ctypes.create_string_buffer(64)
    xkb.xkb_keysym_get_name(keysym, buffer, len(buffer))
    return buffer.value.decode()


def keysym_text(xkb, keysym):
    point = xkb.xkb_keysym_to_utf32(keysym)
    if point < 32 or point == 127:
        return ""
    character = chr(point)
    return "" if unicodedata.category(character) == "Cf" else character


def entry(xkb, keysyms):
    """What one key produces in one state: a label to show and text to type."""
    if not keysyms:
        return None
    names = [keysym_name(xkb, keysym) for keysym in keysyms]
    if len(names) == 1 and names[0].startswith("dead_"):
        return {"keysym": names[0], "label": DEAD_SYMBOLS.get(names[0], ""), "text": "", "dead": names[0]}
    text = "".join(keysym_text(xkb, keysym) for keysym in keysyms)
    label = "◌" + text if len(text) == 1 and unicodedata.combining(text) else text
    return {"keysym": names[0], "label": label, "text": text, "dead": ""}


# Keys that an option such as lv3:ralt_switch or lv3:caps_switch can turn into
# AltGr. The pc model also defines a hidden <LVL3> key, which no one can press.
LEVEL3_KEYS = ("RALT", "CAPS", "LSGT", "BKSL", "MENU", "RWIN", "LWIN", "RCTL", "LALT")


def level3_key(xkb, keymap):
    """The first physical key that selects the third level, or ""."""
    for name in LEVEL3_KEYS:
        if base_keysym_name(xkb, keymap, name) == "ISO_Level3_Shift":
            return name
    return ""


def level3_mask(xkb, keymap, name):
    """The modifier that pressing the AltGr key sets."""
    code = xkb.xkb_keymap_key_by_name(keymap, name.encode()) if name else 0
    if not code:
        return 0
    state = xkb.xkb_state_new(keymap)
    try:
        xkb.xkb_state_update_key(state, code, XKB_KEY_DOWN)
        return xkb.xkb_state_serialize_mods(state, XKB_STATE_MODS_DEPRESSED)
    finally:
        xkb.xkb_state_unref(state)


def base_keysym_name(xkb, keymap, name):
    code = xkb.xkb_keymap_key_by_name(keymap, name.encode())
    if not code:
        return ""
    symbols = ctypes.POINTER(ctypes.c_uint32)()
    count = xkb.xkb_keymap_key_get_syms_by_level(keymap, code, 0, 0, ctypes.byref(symbols))
    return keysym_name(xkb, symbols[0]) if count > 0 else ""


def key_states(xkb, keymap):
    shift = 1 << xkb.xkb_keymap_mod_get_index(keymap, b"Shift")
    lock = 1 << xkb.xkb_keymap_mod_get_index(keymap, b"Lock")
    altgr = level3_key(xkb, keymap)
    level3 = level3_mask(xkb, keymap, altgr)
    codes = {name: xkb.xkb_keymap_key_by_name(keymap, name.encode()) for name in KEYS}
    keys = {name: [None] * 8 for name in KEYS if codes[name]}
    state = xkb.xkb_state_new(keymap)
    try:
        # State index: 1 = Shift, 2 = Caps Lock, 4 = AltGr.
        for index in range(8):
            depressed = (shift if index & 1 else 0) | (level3 if index & 4 else 0)
            locked = lock if index & 2 else 0
            xkb.xkb_state_update_mask(state, depressed, 0, locked, 0, 0, 0)
            for name in keys:
                # get_one_sym applies the Caps Lock capitalization rules that
                # the plain symbol list leaves out.
                one = xkb.xkb_state_key_get_one_sym(state, codes[name])
                if one:
                    keysyms = [one]
                else:
                    symbols = ctypes.POINTER(ctypes.c_uint32)()
                    count = xkb.xkb_state_key_get_syms(state, codes[name], ctypes.byref(symbols))
                    keysyms = [symbols[i] for i in range(max(0, count))]
                keys[name][index] = entry(xkb, keysyms)
    finally:
        xkb.xkb_state_unref(state)
    keys = {name: {"states": states} for name, states in keys.items() if any(states)}
    return keys, altgr if level3 else ""


def compose_table(xkb, context):
    names = [os.environ.get(variable) for variable in ("LC_ALL", "LC_CTYPE", "LANG")]
    for locale in [name for name in names if name] + ["en_US.UTF-8"]:
        table = xkb.xkb_compose_table_new_from_locale(context, locale.encode(), 0)
        if table:
            return table
    return None


def compose_pairs(xkb, context, keys):
    """Dead key + key results from Compose, plus press-and-hold accents."""
    table = compose_table(xkb, context)
    if not table:
        return {}, {}
    state = xkb.xkb_compose_state_new(table, 0)
    try:
        def compose(first, second):
            xkb.xkb_compose_state_reset(state)
            xkb.xkb_compose_state_feed(state, xkb.xkb_keysym_from_name(first.encode(), 0))
            xkb.xkb_compose_state_feed(state, xkb.xkb_keysym_from_name(second.encode(), 0))
            if xkb.xkb_compose_state_get_status(state) != XKB_COMPOSE_COMPOSED:
                return ""
            buffer = ctypes.create_string_buffer(64)
            xkb.xkb_compose_state_get_utf8(state, buffer, len(buffer))
            return buffer.value.decode()

        entries = [e for key in keys.values() for e in key["states"] if e]
        followers = sorted({e["keysym"] for e in entries} | {"space"})
        dead_keys = sorted({e["dead"] for e in entries if e["dead"]})
        pairs = {}
        for dead in dead_keys:
            results = {second: compose(dead, second) for second in followers}
            pairs[dead] = {second: text for second, text in results.items() if text}

        accents = {}
        for e in entries:
            letter = e["text"]
            if len(letter) != 1 or not letter.isalpha() or letter in accents:
                continue
            choices = []
            for dead in ACCENT_DEAD_KEYS:
                text = compose(dead, e["keysym"])
                if len(text) == 1 and text != letter and text not in choices:
                    choices.append(text)
            choices += [extra for extra in EXTRA_ACCENTS.get(letter, "") if extra not in choices]
            if choices:
                accents[letter] = choices[:MAX_ACCENTS]
        return pairs, accents
    finally:
        xkb.xkb_compose_state_unref(state)
        xkb.xkb_compose_table_unref(table)


def describe(layout, variant="", model="", options=""):
    xkb = load_xkb()
    context = xkb.xkb_context_new(0)
    if not context:
        raise RuntimeError("cannot create XKB context")
    try:
        names = RuleNames(None, model.encode() or None, layout.encode(), variant.encode() or None,
                          options.encode() or None)
        keymap = xkb.xkb_keymap_new_from_names(context, ctypes.byref(names), 0)
        if not keymap:
            raise RuntimeError("cannot compile XKB layout " + layout)
        try:
            keys, altgr = key_states(xkb, keymap)
            compose, accents = compose_pairs(xkb, context, keys)
            return {
                "keys": keys,
                "compose": compose,
                "accents": accents,
                "altGrKey": altgr,
            }
        finally:
            xkb.xkb_keymap_unref(keymap)
    finally:
        xkb.xkb_context_unref(context)


if __name__ == "__main__":
    try:
        print(json.dumps(describe(*(sys.argv[1:5])), ensure_ascii=False))
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
