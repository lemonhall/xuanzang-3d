"""Rebuild the bundled CJK font subset from the project's own text.

Usage (from the repository root):

  python tools/font_subset.py --source <NotoSansCJKsc-Regular.otf> \
      --out assets/fonts/noto-sans-sc-subset.otf

Why this exists: Godot's default theme font carries no CJK glyphs, so the HUD
asked the operating system instead (`SystemFont`). That works on Windows and
renders as tofu boxes in a browser, where no such font exists. The export
therefore ships a font, and shipping all 16 MB of Noto Sans CJK to render a few
hundred characters would be silly, so the font is subset to the project's own
text.

The character set is every non-ASCII character found in the project's text
sources (*.gd, *.tscn, *.md, *.cfg, *.json) plus ASCII, CJK punctuation and a
few symbols the UI uses. **Editing a line of dialogue means re-running this
script** -- that is the price of a subset, and the reason it is a script and not
a one-off command someone has to remember.
"""

import argparse
import pathlib

from fontTools import subset

SCAN_SUFFIXES = (".gd", ".tscn", ".md", ".cfg", ".json", ".godot")
SKIP_DIRS = {".godot", ".git"}

# ASCII plus the punctuation a Chinese HUD realistically needs. Anything the
# project actually says is picked up by the scan below; this is the floor.
FLOOR = (
    "".join(chr(c) for c in range(0x20, 0x7F))
    + "　、。〈〉《》「」『』【】〔〕—…·～×÷°％＋－（）"
    + "０１２３４５６７８９"
)


def collect(repo: pathlib.Path) -> str:
    chars = set(FLOOR)
    for path in sorted(repo.rglob("*")):
        if not path.is_file() or path.suffix not in SCAN_SUFFIXES:
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        chars.update(path.read_text(encoding="utf-8", errors="ignore"))
    return "".join(sorted(chars))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--repo", default=".")
    args = parser.parse_args()

    repo = pathlib.Path(args.repo).resolve()
    chars = collect(repo)
    cjk = [c for c in chars if ord(c) > 0x2E7F]
    print("characters kept: %d (CJK units: %d)" % (len(chars), len(cjk)))

    options = subset.Options()
    options.layout_features = ["*"]
    options.drop_tables += ["DSIG"]
    options.recalc_bounds = True
    font = subset.load_font(args.source, options)
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(text=chars)
    subsetter.subset(font)
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    subset.save_font(font, str(out), options)
    print("wrote %s (%.2f MB)" % (out, out.stat().st_size / 1048576))


if __name__ == "__main__":
    main()
