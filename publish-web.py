#!/usr/bin/env python3
"""publish-web.py — generate the website's course pages from the newest syllabus.

Why this exists
---------------
`~/git/website`'s content/courses/*/index.md duplicated the prose of the
syllabi by hand, and had drifted: the pages still described Spring 2025 while
FA26 syllabi were committed here, and one carried a LASSO URL that every
syllabus had already moved off. Same failure the CV pipeline solved years ago
by generating into the site rather than retyping into it.

This is that pipeline for courses, and it deliberately mirrors `~/git/cv`'s
Makefile: this repo OWNS `content/courses/<slug>/index.md` in the website
repo. Hand edits there survive a commit and are destroyed by the next run.

What it does NOT do
-------------------
It does not commit or push. The website repo gates publishing behind
`scripts/ship.sh`, which runs preflight and refuses on failure; committing from
here would route around that gate. Run this, review the diff, then ship from
the website repo.

It does not touch anything else in the page bundle, so `cover.avif` /
`cover.jpg` and their captions are safe.

Front matter
------------
Hugo front matter is per-course and hand-maintained in `web/<course>.md` — it
carries the cover image, alt text, caption, summary and description, none of
which exist in a syllabus. The body below it is generated. Seeded once from the
live pages; edit `web/<course>.md` to change it.

Usage
-----
    ./publish-web.py                 # regenerate every course that has web/<course>.md
    ./publish-web.py --course 1493   # just one
    ./publish-web.py --dry-run       # show what would change, write nothing
    WEBSITE=/path/to/site ./publish-web.py
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WEB = ROOT / "web"
WEBSITE = Path(os.environ.get("WEBSITE", Path.home() / "git" / "website"))

# Same shape build.sh treats as a syllabus, plus the course number and the
# optional descriptor ("Online", "(MWF)") that decides delivery mode.
SYLLABUS_RE = re.compile(r"^(FA|SP|SU)(\d{2}) HIST (\d{4})(.*)\.md$")
SEASON = {"SP": ("Spring", 0), "SU": ("Summer", 1), "FA": ("Fall", 2)}

# Verbatim from the existing pages, curly apostrophe included, so regenerating
# does not show up as a gratuitous diff.
CANVAS_NOTICE = (
    "*If you are enrolled in one of my courses make sure you consult the "
    "current syllabus on the course’s Canvas page*"
)


def newest_syllabus(course: str) -> tuple[Path, str, int, str] | None:
    """The most recent syllabus for a course: (path, season, year, descriptor)."""
    best = None
    for p in ROOT.rglob("*.md"):
        if "templates" in p.parts or "web" in p.parts:
            continue
        m = SYLLABUS_RE.match(p.name)
        if not m or m.group(3) != course:
            continue
        term, yy, _, desc = m.groups()
        season, order = SEASON[term]
        key = (2000 + int(yy), order)
        if best is None or key > best[0]:
            best = (key, p, season, desc.strip())
    if best is None:
        return None
    (year, _), path, season, desc = best
    return path, season, year, desc


def transform(src: str) -> str:
    """Syllabus markdown -> website page body.

    Two changes only:

    * the pandoc title block (`% ...` lines) is dropped — the page title comes
      from Hugo front matter;
    * headings are renumbered so the top level becomes `##`, since `#` is the
      page title on the site.

    Heading levels are assigned from NESTING DEPTH rather than by adding one to
    the source level. The syllabi jump from `##` straight to `####` under
    Assignments, and a naive +1 would carry that skip onto the site as an
    invalid heading order — an accessibility problem the website's own a11y
    lint would flag.
    """
    lines = src.splitlines()
    i = 0
    while i < len(lines) and (lines[i].startswith("%") or not lines[i].strip()):
        i += 1

    out: list[str] = []
    stack: list[int] = []
    in_fence = False
    for line in lines[i:]:
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
        m = re.match(r"^(#{1,6})\s+(.*)$", line)
        if m and not in_fence:
            level = len(m.group(1))
            while stack and stack[-1] >= level:
                stack.pop()
            stack.append(level)
            out.append("#" * min(len(stack) + 1, 6) + " " + m.group(2))
        else:
            out.append(line)
    return "\n".join(out).strip()


def render(course: str, dry: bool) -> bool:
    header_file = WEB / f"{course}.md"
    front = header_file.read_text().rstrip("\n")

    found = newest_syllabus(course)
    if found is None:
        print(f"  {course}: no syllabus found — skipped", file=sys.stderr)
        return False
    path, season, year, desc = found

    mode = "online" if "online" in desc.lower() else "in-person"
    notice = (f"*This course was last offered {mode} during the "
              f"{season} {year} semester*")

    page = "\n\n".join([front, notice, CANVAS_NOTICE, transform(path.read_text())]) + "\n"

    dest = WEBSITE / "content" / "courses" / course / "index.md"
    if not dest.parent.is_dir():
        print(f"  {course}: {dest.parent} does not exist — skipped", file=sys.stderr)
        return False

    old = dest.read_text() if dest.exists() else ""
    if old == page:
        print(f"  {course}: unchanged  (from {path.relative_to(ROOT)})")
        return False

    print(f"  {course}: {'would update' if dry else 'updated'}  "
          f"(from {path.relative_to(ROOT)})")
    if not dry:
        dest.write_text(page)
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--course", metavar="NNNN", help="only this course number")
    ap.add_argument("--dry-run", action="store_true", help="write nothing")
    ap.add_argument("--quiet", action="store_true",
                    help="print nothing; with --dry-run this is a check mode")
    args = ap.parse_args()

    if not WEB.is_dir():
        sys.exit(f"error: {WEB} does not exist (it holds the per-course front matter)")
    if not WEBSITE.is_dir():
        sys.exit(f"error: website repo not found at {WEBSITE} (set WEBSITE=)")

    courses = sorted(p.stem for p in WEB.glob("*.md"))
    if args.course:
        if args.course not in courses:
            sys.exit(f"error: no web/{args.course}.md — create it to publish that course")
        courses = [args.course]

    if not args.quiet:
        print(f"Publishing into {WEBSITE}/content/courses/")

    import contextlib, io
    sink = io.StringIO() if args.quiet else None
    with contextlib.redirect_stdout(sink) if args.quiet else contextlib.nullcontext():
        changed = sum(render(c, args.dry_run) for c in courses)

    if args.quiet:
        # Check mode: exit 1 means the site is behind the syllabi. dots status
        # probes this rather than reimplementing the comparison.
        return 1 if changed else 0

    if changed and not args.dry_run:
        print(f"\n{changed} page(s) updated. Review and ship from the website repo:\n"
              f"    cd {WEBSITE} && git diff content/courses\n"
              f"    scripts/ship.sh \"Update course pages from syllabi\"")
    elif not changed:
        print("\nNothing to do.")
    return 1 if (changed and args.dry_run) else 0


if __name__ == "__main__":
    sys.exit(main())
