#!/usr/bin/env python3
"""check-boilerplate.py — report where a committed syllabus's policy text has
drifted from the canonical snippets in templates/.

Why this exists
---------------
templates/ is consumed by new.sh at SCAFFOLD time only. Every syllabus is
hand-edited afterwards, so the generated text and the committed text diverge
legitimately and there is no re-render step. That is fine for a schedule or a
grade table. It is not fine for policy text that is quoted from the university
-- a Title IX notice should not vary by transcription.

This script is the check that closes that gap, and it is ADVISORY on purpose:
a deliberate one-off policy change for a single course is legitimate, so this
never runs inside build.sh and never blocks a commit.

Variant groups
--------------
Some policy blocks have more than one correct form. HIST 1493 is a large
survey taught with TAs and needs the plural reporting notice; a solo-taught
course needs the singular one. Both are canonical. VARIANT_GROUPS below maps a
policy to every snippet file that is an accepted form of it.

Because new.sh's include regex accepts [A-Za-z0-9_-]+, each variant is a
normal includable snippet: {{include mandatory-reporting-tas}} resolves to
templates/common/mandatory-reporting-tas.md with no script change.

Usage
-----
    ./check-boilerplate.py              report drift
    ./check-boilerplate.py --fix        rewrite UNAMBIGUOUS drift to canonical
    ./check-boilerplate.py --group mandatory-reporting    check one policy only

Exit status is 0 unless --strict is passed, in which case any drift exits 1.
"""
from __future__ import annotations

import argparse
import difflib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
TEMPLATES = ROOT / "templates"
SNIPPET_DIRS = ("common", "inperson", "online")

# A policy -> the snippet files that are accepted canonical forms of it.
# A policy not listed here is its own group, with every same-named file across
# common/ inperson/ online/ treated as an accepted variant (that is already how
# new.sh resolves an include).
VARIANT_GROUPS: dict[str, tuple[str, ...]] = {
    "mandatory-reporting": ("mandatory-reporting", "mandatory-reporting-tas"),
}

# A syllabus is a term-prefixed file, matching build.sh's filter exactly.
SYLLABUS_RE = re.compile(r"^(FA|SP|SU)(\d{2}) ")

# Policy blocks that are quoted from the university and must not vary by
# transcription. Everything else in templates/ is a starting point a course is
# EXPECTED to edit -- contact.md carries office hours and TA details, drops.md
# carries per-semester dates -- so checking those reports noise, not drift.
INVARIANT = {
    "mandatory-reporting",
    "accessibility",
    "academic-integrity",
    "incomplete-grades",
    "grade-disputes",
    "resources",
}

# A paragraph this similar to a canonical snippet IS that policy block, however
# it has drifted. Well clear of the similarity between two unrelated policies.
DETECT_RATIO = 0.75


def term_year(name: str) -> int:
    return 2000 + int(SYLLABUS_RE.match(name).group(2))


def show_diff(canonical: str, found: str, label: str, rel) -> None:
    for line in difflib.unified_diff(canonical.split(), found.split(),
                                     lineterm="", n=2,
                                     fromfile=label, tofile=str(rel)):
        if line.startswith(("+", "-")) and not line.startswith(("+++", "---")):
            print(f"       {line}")


def norm(text: str) -> str:
    """Collapse whitespace so a rewrapped paragraph is not reported as drift."""
    return re.sub(r"\s+", " ", text).strip()


def paragraphs(text: str) -> list[tuple[int, str]]:
    """Yield (line index, block) for each blank-line-separated block."""
    out, buf, start = [], [], 0
    for i, line in enumerate(text.splitlines()):
        if line.strip():
            if not buf:
                start = i
            buf.append(line)
        elif buf:
            out.append((start, "\n".join(buf)))
            buf = []
    if buf:
        out.append((start, "\n".join(buf)))
    return out


def load_groups(only: str | None) -> dict[str, dict[str, str]]:
    """policy name -> {snippet path label: canonical text}."""
    by_name: dict[str, dict[str, str]] = {}
    for d in SNIPPET_DIRS:
        for f in sorted((TEMPLATES / d).glob("*.md")):
            by_name.setdefault(f.stem, {})[f"{d}/{f.name}"] = norm(f.read_text())  # noqa: E501

    groups: dict[str, dict[str, str]] = {}
    claimed: set[str] = set()
    for policy, members in VARIANT_GROUPS.items():
        merged: dict[str, str] = {}
        for m in members:
            merged.update(by_name.get(m, {}))
            claimed.add(m)
        if merged:
            groups[policy] = merged
    for name, variants in by_name.items():
        if name not in claimed:
            groups[name] = variants
    if only:
        groups = {k: v for k, v in groups.items() if k == only}
        if not groups:
            sys.exit(f"error: no policy group named {only!r}")
    return groups


def discriminative_spans(variant: str, others: list[str]) -> list[str]:
    """Token runs that distinguish `variant` from every other accepted form.

    Identity has to be decided on the words that actually differ between the
    variants, not on overall similarity: the two reporting notices are 98%
    alike, so a similarity margin can't tell "solo course, miscapitalized" from
    "TA course, miscapitalized" -- but the clause "a university employee I am"
    vs "University employees I (and the TAs) are" can, exactly.
    """
    spans: list[str] = []
    v = variant.split()
    for other in others:
        sm = difflib.SequenceMatcher(None, v, other.split())
        for tag, i1, i2, _, _ in sm.get_opcodes():
            if tag in ("replace", "delete") and i2 > i1:
                spans.append(" ".join(v[i1:i2]).lower())
    return spans


def identify(block: str, variants: dict[str, str]) -> str | None:
    """Which accepted form is this block a (possibly drifted) copy of?

    Returns a label, or None when the block agrees with no variant's
    distinguishing clause -- which is the SP26 3703 case, a hybrid of two
    forms. That genuinely needs a human, so it is reported, never guessed.
    """
    low = " ".join(block.lower().split())

    def present(span: str) -> bool:
        # Word-boundary match, not substring: "employee" must not be satisfied
        # by "employees". That distinction is the whole signal here -- the one
        # syllabus reading "a university employees I am" is a hybrid of both
        # forms, and matching loosely would silently file it under one of them.
        return re.search(rf"(?<!\w){re.escape(span)}(?!\w)", low) is not None

    hits = [label for label, text in variants.items()
            if all(present(sp) for sp in
                   discriminative_spans(text, [t for l, t in variants.items() if l != label]))]
    return hits[0] if len(hits) == 1 else None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fix", action="store_true",
                    help="rewrite unambiguous drift to the closest canonical form")
    ap.add_argument("--group", metavar="NAME", help="check only this policy group")
    ap.add_argument("--strict", action="store_true",
                    help="exit 1 if any drift remains (for CI)")
    ap.add_argument("--since", type=int, metavar="YEAR", default=None,
                    help="oldest term year to check (default: the current year)")
    ap.add_argument("--all-years", action="store_true",
                    help="check every term, including past ones — see note below")
    ap.add_argument("--all-policies", action="store_true",
                    help="check every snippet, not just the invariant policy blocks")
    args = ap.parse_args()

    groups = load_groups(args.group)
    if not args.all_policies and not args.group:
        groups = {k: v for k, v in groups.items() if k in INVARIANT}

    # Past syllabi are the historical record of what students were actually
    # handed. A 2018 syllabus naming the office "Student Disability Services,
    # 315 Student Union" is not drift -- that was its name. Rewriting it would
    # falsify the record, so history is out of scope unless asked for.
    import datetime
    since = args.since if args.since is not None else datetime.date.today().year
    if args.all_years:
        since = 0

    files = sorted(p for p in ROOT.rglob("*.md")
                   if "templates" not in p.parts and SYLLABUS_RE.match(p.name)
                   and term_year(p.name) >= since)

    drift = ambiguous = fixed = checked = 0

    for path in files:
        original = path.read_text()
        text = original
        rel = path.relative_to(ROOT)

        for name, variants in groups.items():
            # Several snippets are more than one paragraph (accessibility and
            # grade-disputes each carry a bold follow-up line). Comparing a
            # single paragraph against a two-paragraph canonical always looks
            # like a deletion, so slide a window the width of the widest
            # variant over the document instead.
            span = max(len([b for b in v.split("\n\n") if b.strip()])
                       for v in variants.values())
            paras = paragraphs(text)
            windows = []
            for size in range(1, span + 1):
                for i in range(len(paras) - size + 1):
                    windows.append("\n\n".join(b for _, b in paras[i:i + size]))

            for block in windows:
                n = norm(block)
                if n in variants.values():
                    break                    # matches an accepted form exactly

                # Detect by similarity rather than by a fixed opening phrase:
                # SU26 HIST 1103 drops a word from the first sentence, so an
                # anchored match misses it silently -- the exact failure this
                # check exists to catch.
                scored = sorted(
                    ((difflib.SequenceMatcher(None, n, c).ratio(), label, c)
                     for label, c in variants.items()),
                    reverse=True,
                )
                if not scored or scored[0][0] < DETECT_RATIO:
                    continue
                checked += 1
                best = scored[0]

                chosen = identify(n, variants)
                if chosen is None:
                    drift += 1
                    ambiguous += 1
                    print(f"DRIFT  {rel}")
                    print(f"       policy: {name}")
                    print(f"       AMBIGUOUS — matches no variant's distinguishing "
                          f"clause; closest is {best[1]} ({best[0]:.3f}).")
                    print("       Decide which form this course should use, then edit by hand.")
                    show_diff(best[2], n, best[1], rel)
                    break

                canonical = variants[chosen]
                if args.fix:
                    text = text.replace(block, canonical, 1)
                    fixed += 1
                    print(f"FIXED  {rel}  ({name} -> {chosen})")
                else:
                    drift += 1
                    print(f"DRIFT  {rel}")
                    print(f"       policy: {name}  →  {chosen}")
                    show_diff(canonical, n, chosen, rel)
                break

        if args.fix and text != original:
            path.write_text(text)

    scope = "all terms" if args.all_years else f"{since} and later"
    print(f"\n{len(files)} syllabi ({scope}), {len(groups)} policy groups, "
          f"{checked} blocks checked")
    if args.fix:
        print(f"{fixed} fixed, {drift} left for review")
    else:
        print(f"{drift} drifted" + (f" ({ambiguous} ambiguous)" if ambiguous else ""))
    if drift and not args.fix:
        print("\nReview each, then either edit the syllabus or — if the syllabus is "
              "right and\ntemplates/ is stale — update the snippet so future "
              "scaffolds inherit the fix.")
    return 1 if (args.strict and drift) else 0


if __name__ == "__main__":
    sys.exit(main())
