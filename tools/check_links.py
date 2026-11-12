#!/usr/bin/env python3
"""Check that every relative link/image in the markdown files points to an existing file."""
import re, sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
bad = []
n = 0
for md in ROOT.rglob("*.md"):
    if ".git" in md.parts:
        continue
    text = md.read_text(encoding="utf-8")
    text = re.sub(r"```.*?```", "", text, flags=re.S)  # ignore code blocks
    for m in re.finditer(r"!?\[[^\]]*\]\(([^)\s]+)\)", text):
        target = m.group(1)
        if re.match(r"^(https?:|mailto:|#)", target):
            continue
        path = unquote(target.split("#")[0])
        if not path:
            continue
        n += 1
        if not (md.parent / path).exists():
            bad.append(f"{md.relative_to(ROOT)}: broken link -> {target}")
if bad:
    print("\n".join(bad)); sys.exit(1)
print(f"OK: {n} relative links resolve.")
