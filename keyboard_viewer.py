#!/usr/bin/env python3
"""Print printable key labels for one XKB layout as JSON."""

import ctypes
import ctypes.util
import json
import sys
import unicodedata


KEYS = (
    "TLDE AE01 AE02 AE03 AE04 AE05 AE06 AE07 AE08 AE09 AE10 AE11 AE12 "
    "AD01 AD02 AD03 AD04 AD05 AD06 AD07 AD08 AD09 AD10 AD11 AD12 BKSL "
    "AC01 AC02 AC03 AC04 AC05 AC06 AC07 AC08 AC09 AC10 AC11 "
    "LSGT AB01 AB02 AB03 AB04 AB05 AB06 AB07 AB08 AB09 AB10"
).split()

DEAD_SYMBOLS = {
    "dead_acute": "´", "dead_grave": "`", "dead_circumflex": "^",
    "dead_tilde": "~", "dead_diaeresis": "¨", "dead_cedilla": "¸",
    "dead_caron": "ˇ", "dead_breve": "˘", "dead_abovering": "˚",
    "dead_macron": "¯", "dead_doubleacute": "˝", "dead_ogonek": "˛",
    "dead_abovedot": "˙", "dead_belowdot": "·",
}


class RuleNames(ctypes.Structure):
    _fields_ = [(field, ctypes.c_char_p) for field in ("rules", "model", "layout", "variant", "options")]


def labels(layout, variant="", model="", options=""):
    library = ctypes.util.find_library("xkbcommon")
    if not library:
        raise RuntimeError("libxkbcommon is unavailable")
    xkb = ctypes.CDLL(library)
    xkb.xkb_context_new.argtypes = [ctypes.c_int]
    xkb.xkb_context_new.restype = ctypes.c_void_p
    xkb.xkb_context_unref.argtypes = [ctypes.c_void_p]
    xkb.xkb_keymap_new_from_names.argtypes = [ctypes.c_void_p, ctypes.POINTER(RuleNames), ctypes.c_int]
    xkb.xkb_keymap_new_from_names.restype = ctypes.c_void_p
    xkb.xkb_keymap_unref.argtypes = [ctypes.c_void_p]
    xkb.xkb_keymap_key_by_name.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    xkb.xkb_keymap_key_by_name.restype = ctypes.c_uint32
    xkb.xkb_keymap_key_get_syms_by_level.argtypes = [
        ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32,
        ctypes.POINTER(ctypes.POINTER(ctypes.c_uint32)),
    ]
    xkb.xkb_keymap_key_get_syms_by_level.restype = ctypes.c_int
    xkb.xkb_keysym_to_utf32.argtypes = [ctypes.c_uint32]
    xkb.xkb_keysym_to_utf32.restype = ctypes.c_uint32
    xkb.xkb_keysym_get_name.argtypes = [ctypes.c_uint32, ctypes.c_char_p, ctypes.c_size_t]
    xkb.xkb_keysym_get_name.restype = ctypes.c_int

    context = xkb.xkb_context_new(0)
    if not context:
        raise RuntimeError("cannot create XKB context")
    names = RuleNames(None, model.encode() or None, layout.encode(), variant.encode() or None,
                      options.encode() or None)
    keymap = xkb.xkb_keymap_new_from_names(context, ctypes.byref(names), 0)
    if not keymap:
        xkb.xkb_context_unref(context)
        raise RuntimeError("cannot compile XKB layout " + layout)
    try:
        result = {}
        for name in KEYS:
            code = xkb.xkb_keymap_key_by_name(keymap, name.encode())
            if not code:
                continue
            levels = []
            keysyms = []
            for level in range(4):
                symbols = ctypes.POINTER(ctypes.c_uint32)()
                count = xkb.xkb_keymap_key_get_syms_by_level(keymap, code, 0, level,
                                                              ctypes.byref(symbols))
                chars = []
                symbol_names = []
                for index in range(max(0, count)):
                    point = xkb.xkb_keysym_to_utf32(symbols[index])
                    symbol_name = ctypes.create_string_buffer(64)
                    xkb.xkb_keysym_get_name(symbols[index], symbol_name, len(symbol_name))
                    symbol_names.append(symbol_name.value.decode())
                    if point >= 32 and point != 127:
                        character = chr(point)
                        if unicodedata.category(character) == "Cf":
                            continue
                        chars.append("◌" + character if unicodedata.combining(character) else character)
                    else:
                        chars.append(DEAD_SYMBOLS.get(symbol_name.value.decode(), ""))
                levels.append("".join(chars))
                keysyms.append(symbol_names)
            result[name] = {"labels": levels, "keysyms": keysyms}
        return result
    finally:
        xkb.xkb_keymap_unref(keymap)
        xkb.xkb_context_unref(context)


if __name__ == "__main__":
    try:
        print(json.dumps(labels(*(sys.argv[1:5])), ensure_ascii=False))
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
