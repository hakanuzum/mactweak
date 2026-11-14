#!/usr/bin/env python3
"""Splits KDE Aurorae window-decoration buttons into one SVG per state.

An Aurorae button file (close.svg, minimize.svg, maximize.svg) draws every state
in one document, as elements with the ids active-center, hover-center,
pressed-center and inactive-center. This writes
<out>/<button>-<state>.svg with only that state's element kept, in the layout
tools/pack_button_themes.swift reads (close/min/max x normal/hover/pressed/inactive).

    python3 tools/aurorae_buttons.py <dir with close.svg ...> <out dir>
"""
import copy
import os
import sys
import xml.etree.ElementTree as ET

SVG = "{http://www.w3.org/2000/svg}"
BUTTONS = {"close": "close", "minimize": "min", "maximize": "max"}
STATES = {"active": "normal", "hover": "hover", "pressed": "pressed", "inactive": "inactive"}
ALL_IDS = {f"{s}-center" for s in ("active", "hover", "pressed", "inactive", "deactivated")}

for prefix, uri in (("", "http://www.w3.org/2000/svg"), ("xlink", "http://www.w3.org/1999/xlink"),
                    ("inkscape", "http://www.inkscape.org/namespaces/inkscape"),
                    ("sodipodi", "http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd")):
    ET.register_namespace(prefix, uri)


def remove_ids(root, ids):
    """Removes every element whose id is in ids (at any depth)."""
    for parent in root.iter():
        for child in list(parent):
            if child.get("id") in ids:
                parent.remove(child)


src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
for file, button in BUTTONS.items():
    path = os.path.join(src, f"{file}.svg")
    if not os.path.exists(path):
        continue
    tree = ET.parse(path)
    present = {e.get("id") for e in tree.getroot().iter()} & ALL_IDS
    for state, name in STATES.items():
        keep = f"{state}-center"
        if keep not in present:
            keep = "active-center"  # theme has no art for this state
        root = copy.deepcopy(tree.getroot())
        remove_ids(root, ALL_IDS - {keep})
        ET.ElementTree(root).write(os.path.join(out, f"{button}-{name}.svg"), xml_declaration=True, encoding="utf-8")
print("split:", src)
