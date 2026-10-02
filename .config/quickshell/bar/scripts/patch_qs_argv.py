#!/usr/bin/env python3
# One-shot build helper for the patched noctalia-qs (QtWebEngine argv fix).
import pathlib, sys

p = pathlib.Path("/tmp/noctalia-qs-src/src/launch/launch.cpp")
src = p.read_text()
old = "\tauto qArgC = 0;"
if old not in src:
    # tab-vs-spaces fallback
    for line in src.splitlines():
        if "auto qArgC = 0;" in line:
            old = line
            break
assert old in src, "anchor not found"
new = (
    "\t// hyprcandy patch: QtWebEngine requires QCoreApplication::arguments() to be\n"
    "\t// non-empty (Chromium base::CommandLine needs the program name); argc=0 made\n"
    "\t// every WebEngineView qFatal. argc=1 exposes only argv[0], so Qt still never\n"
    "\t// parses qs's own CLI flags.\n"
    "\tauto qArgC = (argv != nullptr && argv[0] != nullptr) ? 1 : 0;"
)
src = src.replace(old, new, 1)
p.write_text(src)
print("patched:", p)
