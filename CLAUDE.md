# syllabi — session notes

Operational knowledge for working on this repo: the things that are
counterintuitive or that silently do nothing. README.md covers what the scripts
do and how to call them — that is not repeated here.

**What belongs here:** a fact a future session would otherwise get wrong.
**What does NOT:** usage (README.md), per-change rationale (a code comment),
a log of what a pass changed (git history).

## What this repo is

Markdown syllabi for OSU History courses, compiled to web-optimized PDFs by
`build.sh` (pandoc → tectonic → ghostscript → qpdf). Remote is
`github:jleberle/syllabi.git`, branch `main`.

## Things that silently do nothing

### templates/ only affects files that do not exist yet

`templates/` is consumed by `new.sh` at **scaffold time**. Editing
`templates/common/mandatory-reporting.md` changes what the *next* stub
contains and touches no existing syllabus. There is no re-render step and
there cannot be one — each syllabus is hand-edited after scaffolding, so the
generated text and the committed text diverge legitimately.

Consequence: a policy fix applied to `templates/` is **not** applied to the
course you are teaching. Fix both, and see `check-boilerplate.py` below.

### The build ignores files without a term prefix

`build.sh` only treats `FA|SP|SU` + two digits as a syllabus. Handouts, policy
addenda, and revised schedules in a semester folder are skipped by design — so
a file that "won't build" is usually named wrong, not broken. Same filter
applies in `Supplemental/`.

### The pre-commit hook is off until you turn it on

Git does not track `.git/hooks/`. Once per clone:

```bash
git config core.hooksPath hooks
```

Without it `hooks/pre-commit` never runs and a broken `build.sh` commits
cleanly. The hook is also path-gated — it fires only for changes to
`build.sh`, `new.sh`, `test.sh`, `syllabus.tex`, or `templates/`, so a
Markdown-only commit is deliberately unaffected.

## bash 3.2 is not enough

`build.sh` and `test.sh` use `wait -n` (bash ≥ 4.3). macOS ships 3.2, so both
scripts hard-exit with a version check. `brew install bash`. This bites on a
fresh machine and the error is explicit, but it is the first thing to check
when either script refuses to start.

## PDFs are build output, not content

`PDFs/` and `*.pdf` are gitignored, with one exception whitelisted:
`!osulogo.pdf`, which the LaTeX template needs. So the compiled syllabi exist
only on the machine that built them — nothing downstream can link to a PDF in
this repo. (`publish-web.py` generates Markdown for the website instead, for
exactly this reason.)

## Boilerplate has forked, and the canonical text is a live question

The Mandatory Reporting Notice exists in **five** forms across the committed
syllabi. The split is not random:

- **HIST 1493** (large survey, taught with TAs) uses "As University employees I
  (and the TAs) are…" — consistent since FA24 and *correct for that course*.
  Canonicalized as `templates/common/mandatory-reporting-tas.md`.
- **Solo-taught courses** use "As a university employee I am…" —
  `templates/common/mandatory-reporting.md`.
- Three further forms are transcription drift: capital "University employee",
  a dropped "kept" in `SU26 HIST 1103 Online`, and `SP26 HIST 3703`'s
  "As a university employees I am", a hybrid of both forms.

So there are **two legitimate variants plus drift**, and course format is *not*
a reliable proxy for which applies — HIST 3703 is in-person but solo-taught, so
putting the TA form in `inperson/` would give it the wrong text. That is why
both live in `common/` and are selected explicitly:
`{{include mandatory-reporting-tas}}` (new.sh's include regex accepts hyphens,
so this needs no script change).

### check-boilerplate.py

```bash
./check-boilerplate.py                 # current-year syllabi, invariant policies
./check-boilerplate.py --fix           # rewrite only UNAMBIGUOUS drift
./check-boilerplate.py --all-years --all-policies    # everything
```

Advisory by design — it never runs in `build.sh` and never blocks a commit,
because a deliberate one-off policy change for a single course is legitimate.

Three scoping decisions in it are load-bearing; read them before widening it:

1. **Past terms are out of scope by default.** A syllabus becomes archival the
   moment its semester ends — it is then the record of what those students were
   handed, not a document anyone can still act on. A 2018 syllabus naming the
   office "Student Disability Services, 315 Student Union" is not drift; that
   was its name. Scope therefore follows the TERM in session, not the calendar
   year: in September, that spring's syllabi are already history. `--since FA26`
   or `--all-years` opts in.
2. **Only `INVARIANT` policies are checked by default** — the blocks quoted
   from the university. `contact.md` carries office hours and TA details and
   `drops.md` carries per-semester dates; both are *supposed* to differ per
   course, so checking them reports noise. `--all-policies` opts in.
3. **Identity is decided on distinguishing clauses, not similarity.** The two
   reporting notices are 98% alike, so a similarity margin cannot tell "solo
   course, miscapitalized" from "TA course, miscapitalized". Matching is
   word-boundary aware for the same reason: "employee" must not be satisfied by
   "employees", which is precisely what makes `SP26 HIST 3703` report as
   ambiguous rather than being silently filed under one form.

### Decided 2026-09-12

- **Casing is lowercase**: "As a university employee I am…". The template was
  already correct and stays canonical; the capitalized copies are drift.
- **Archival means archival.** Typos in a syllabus whose term has ended are not
  fixed — including `SP26 HIST 3703`'s "As a university employees I am" and its
  missing FERPA paragraph. Both are out of scope by default now.

### Open, as of 2026-09-12

One live-term question, in `FA26 HIST 1493`. The SAS follow-up sentence has five
wordings across the repo's history, and the in-person courses do not use the
in-person template's version:

| Sentence | Used by |
|---|---|
| "Students wishing to use SAS accommodations **must see me in office hours to discuss their accommodations**" | 6 syllabi, incl. `FA26 HIST 1493` |
| "Students wishing to use SAS accommodations **need to schedule a meeting with me as soon as possible**" | 5 syllabi — this is `templates/online/accessibility.md` |
| "**If you have an SAS accommodation** you need to see me during office hours…" | 3 syllabi, all HIST 3703 — this is `templates/common/accessibility.md` |
| two further one-off wordings | `FA21 HIST 1493 (Small)`, `FA25 HIST 1493` |

`FA26 HIST 1103 Online` matches its template exactly. The open question is only
whether `templates/common/accessibility.md` should adopt the wording the
in-person syllabi actually use ("must see me in office hours…"), which would
make the template match practice instead of the reverse.

## Publishing to the website

`./publish-web.py` generates `website/content/courses/<course>/index.md` from
the newest syllabus for each course. See that script's header for the
contract; the important half is that it **owns** those files — hand edits to
`content/courses/*/index.md` are overwritten on the next run. The website repo
is assumed at `~/git/website`; override with `WEBSITE`.

This deliberately mirrors `~/git/cv`'s `make publish`, which owns
`website/content/cv/` the same way.

## Verification

`./test.sh` runs both scripts in a temp sandbox and never touches the real
tree. `--no-build` skips the PDF smoke tests and needs no toolchain. Run it
after editing either script — and note that with `shellcheck` installed it
also asserts the scripts stay lint-clean, so a shellcheck upgrade can fail the
suite without any change here.
