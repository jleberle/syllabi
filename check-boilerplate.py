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
import datetime
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


# Season ordering within a year, so terms compare as (year, season).
TERM_ORDER = {"SP": 0, "SU": 1, "FA": 2}


def term_key(name: str) -> tuple[int, int]:
    m = SYLLABUS_RE.match(name)
    return (2000 + int(m.group(2)), TERM_ORDER[m.group(1)])


def current_term() -> tuple[int, int]:
    """The term in session now.

    A syllabus becomes archival the moment its semester ends -- it is then the
    record of what those students were handed, not a document anyone can still
    act on. So scope follows the TERM, not the calendar year: in September,
    that spring's syllabi are already history even though the year is not over.
    Month boundaries are approximate on purpose; being a week off at a term
    boundary only ever includes one extra term in an advisory report.
    """
    today = datetime.date.today()
    season = 0 if today.month <= 5 else (1 if today.month <= 7 else 2)
    return (today.year, season)


def parse_since(value: str) -> tuple[int, int]:
    """Accept a term code (FA26, SP25) or a bare year (2024 -> from Spring)."""
    v = value.strip().upper()
    if len(v) == 4 and v[:2] in TERM_ORDER and v[2:].isdigit():
        return (2000 + int(v[2:]), TERM_ORDER[v[:2]])
    if v.isdigit():
        return (int(v), 0)
    raise argparse.ArgumentTypeError(
        f"expected a term like FA26 or a year like 2026, got {value!r}")


def _wrap(prefix: str, text: str, width: int = 96) -> None:
    body = " ".join(text.split())
    pad = " " * (7 + len(prefix))
    first = True
    while body:
        take = width if len(body) > width else len(body)
        if take < len(body):
            cut = body.rfind(" ", 0, take)
            take = cut if cut > 0 else take
        print(f"       {prefix}{body[:take]}" if first else f"{pad}{body[:take]}")
        body = body[take:].lstrip()
        first = False


def show_diff(canonical: str, found: str, label: str, rel) -> None:
    """Report which PARAGRAPH differs, quoting both sides.

    A word-level diff of a policy paragraph is unreadable -- a reworded
    sentence comes out as a shredded interleaving of single words. What the
    reader needs is which paragraph moved and what each side actually says.
    """
    cp = [b for b in canonical.split("\n\n") if b.strip()]
    fp = [b for b in found.split("\n\n") if b.strip()]
    sm = difflib.SequenceMatcher(None, [norm(x) for x in cp], [norm(x) for x in fp])
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            continue
        for c in cp[i1:i2]:
            _wrap(f"{label}: ", c)
        for f in fp[j1:j2]:
            _wrap("this syllabus: ", f)


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
            # Stored RAW, not normalized: norm() collapses the blank line
            # between paragraphs, which would report every multi-paragraph
            # policy as one paragraph (so the sliding window never widened)
            # and would make --fix write back a paragraph-collapsed block.
            # Normalization happens at comparison time instead.
            by_name.setdefault(f.stem, {})[f"{d}/{f.name}"] = f.read_text().strip()

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
    v = norm(variant).split()
    for other in others:
        sm = difflib.SequenceMatcher(None, v, norm(other).split())
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
    ap.add_argument("--since", type=parse_since, metavar="TERM", default=None,
                    help="oldest term to check, e.g. FA26 or 2026 "
                         "(default: the term in session)")
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
    since = args.since if args.since is not None else current_term()
    if args.all_years:
        since = (0, 0)

    files = sorted(p for p in ROOT.rglob("*.md")
                   if "templates" not in p.parts and "web" not in p.parts
                   and SYLLABUS_RE.match(p.name)
                   and term_key(p.name) >= since)

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
                    windows.append((i, size,
                                    "\n\n".join(b for _, b in paras[i:i + size])))

            # Detect by similarity rather than by a fixed opening phrase:
            # SU26 HIST 1103 drops a word from the first sentence, so an
            # anchored match misses it silently -- the exact failure this
            # check exists to catch.
            #
            # Score EVERY window and keep the best. Taking the first window
            # over the detection threshold instead reports a two-paragraph
            # policy whose second paragraph was swapped as if that paragraph
            # had been deleted: the one-paragraph window matches well enough to
            # win on its own, and the replacement text never appears in the
            # diff at all.
            candidates = []
            exact = False
            for start, size, block in windows:
                n = norm(block)
                if n in {norm(v) for v in variants.values()}:
                    exact = True             # matches an accepted form exactly
                    break
                for vlabel, canon in variants.items():
                    r = difflib.SequenceMatcher(None, n, norm(canon)).ratio()
                    if r >= DETECT_RATIO:
                        candidates.append((r, vlabel, canon, n, block, start, size))

            if exact or not candidates:
                continue

            checked += 1
            ratio, vlabel, canon, found, raw, start, size = max(candidates,
                                                               key=lambda t: t[0])

            # A shorter window can outscore the full-width one when a trailing
            # paragraph was REWORDED rather than dropped -- the reworded text
            # drags the wide window's ratio below the narrow one's. Diffing the
            # narrow match then shows the canonical's trailing paragraph as a
            # clean deletion and never shows the replacement, which reads as
            # "this line is missing" when it is actually "this line differs".
            # Widen the displayed text to the canonical's paragraph count.
            canon_paras = len([b for b in canon.split("\n\n") if b.strip()])
            if canon_paras > size:
                shown = "\n\n".join(b for _, b in paras[start:start + canon_paras])
            else:
                shown = raw

            chosen = identify(found, variants)
            if chosen is None:
                drift += 1
                ambiguous += 1
                print(f"DRIFT  {rel}")
                print(f"       policy: {name}")
                print(f"       AMBIGUOUS — matches no variant's distinguishing "
                      f"clause; closest is {vlabel} ({ratio:.3f}).")
                print("       Decide which form this course should use, then edit by hand.")
                show_diff(canon, shown, vlabel, rel)
                continue

            canonical = variants[chosen]
            if args.fix:
                text = text.replace(raw, canonical, 1)
                fixed += 1
                print(f"FIXED  {rel}  ({name} -> {chosen})")
            else:
                drift += 1
                print(f"DRIFT  {rel}")
                print(f"       policy: {name}  →  {chosen}")
                show_diff(canonical, shown, chosen, rel)

        if args.fix and text != original:
            path.write_text(text)

    since_label = {v: k for k, v in TERM_ORDER.items()}.get(since[1], "")
    scope = ("all terms" if args.all_years
             else f"{since_label}{since[0] % 100} and later")
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
