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

The same is true in the other direction, and it is the one that bites:
`templates/skeleton-survey.md` and the `survey/` snippets were *derived from*
`SP27 HIST 1493.md`, but nothing links them. Editing SP27 changes SP27 only;
the next survey scaffold still has the old text. To change what survey courses
start from, edit `skeleton-survey.md`, `survey/`, or `courses/1493/`.

### Three course types, not two formats

`new.sh` picks `survey` (course number < 3000), `upper` (>= 3000) or `online`
(descriptor contains "online"), or takes `--type`. Each has
`templates/skeleton-<type>.md` and a `templates/<type>/` snippet folder that
overrides `templates/common/`. `templates/courses/<course>/` holds content for
one course (`{{include-course name}}`) and is **never** borrowed across
courses: a survey course with no folder gets `[description for HIST 1103]`
placeholders, not 1493's text. Only 1493 has a folder so far.

The weekly rows in `courses/1493/schedule.md` are `| events | topic | textbook |`
with the finals-week row last; `schedule.py` supplies the Wk and Dates columns.
Events name weekdays ("Wed: Source Workshop 2") but never dates, which is what
lets one set of rows serve Spring and Fall. `new.sh` warns when a no-class day
lands on a weekday a row schedules something.

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
`build.sh`, `new.sh`, `schedule.py`, `test.sh`, `syllabus.tex`, `templates/`, or
`calendar/`, so a Markdown-only commit is deliberately unaffected.

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
putting the TA form in a per-type folder like `upper/` would give it the wrong
text. That is why both live in `common/` and are selected explicitly:
`{{include mandatory-reporting-tas}}` (new.sh's include regex accepts hyphens,
so this needs no script change).

The survey template has a **sixth** wording: SP27 HIST 1493 rewrote the TA-form
notice ("All communications are confidential except that, as University
employees, I (and the TAs)…"). It lives in `templates/survey/mandatory-reporting.md`
and is an accepted variant alongside the two in `common/`. `-tas` stays only
because `FA26 HIST 1493` still uses that wording; delete it once FA26 is
archival and nothing scaffolds from it.

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

### The SAS follow-up line

`templates/common/accessibility.md` ends with a bold sentence, set apart from
the ADA paragraph, telling students what to do with an accommodation. Canonical
wording as of 2026-09-12:

> **Students wishing to use SAS accommodations must see me in student hours or
> through a scheduled appointment to discuss their accommodations**

"Student hours" is deliberate and matches the contact block in the syllabi
themselves; earlier copies said "office hours". `templates/online/accessibility.md`
keeps its own wording ("need to schedule a meeting with me as soon as possible")
and was not changed.

Five wordings of this sentence exist across the repo's history. All the older
ones are in archival terms and stay as they are.

Survey scaffolds do not use this line. `templates/survey/accessibility.md` is
SP27's own Accommodations text (no bold follow-up sentence), and `survey/`
likewise overrides `grade-disputes`, `incomplete-grades` and `class-conduct`
with SP27's wording. Those are survey-only; `common/` is unchanged and still
feeds upper-division. Promoting any of them to `common/` is a separate
decision.

### Open, as of 2026-09-12

`FA26 HIST 1493` still reads "must see me in office hours to discuss their
accommodations" and so differs from the canonical text above. **That term is in
session and the syllabus has already been distributed**, so it is not edited
here: changing it now would make a rebuilt PDF disagree with what students were
given. Decide deliberately whether to amend it mid-term or let it stand until
SP27 scaffolds inherit the new wording.

Since the `survey/` snippets were registered, `check-boilerplate.py` also
reports `FA26 HIST 1493`'s grade-disputes paragraph (it says "office hours";
SP27 says "student hours"). Same cause, same answer: FA26 predates SP27's
wording. Both reports end when FA26 does.

## Term calendars

`calendar/<year>-<season>.conf` is where a term's dates live, and `new.sh` reads
it at scaffold time like everything else in this repo: editing a calendar
changes the *next* scaffold, never an existing syllabus.

- **Nothing is inferred.** A blank key leaves a `[placeholder]` in the syllabus;
  the registrar's dates must be typed in. `./new.sh calendar <season> <year>`
  writes the blank file and suggests Labor Day / Thanksgiving week / MLK Day
  commented out. Do not "helpfully" fill in a future term from last year's
  offsets: they are not constant (Spring 2026 and 2027 withdraw deadlines are
  88 days after the start, Fall 2026's is 81).
- `finals` sets the week count (start's Monday through finals' Monday). Without
  it, 17 weeks for Fall/Spring and 8 for Summer.
- Flags (`--start`, `--drop-*`) override the calendar per syllabus. Unknown keys
  and malformed dates are errors on purpose, so a typo cannot silently drop a
  deadline.
- Deadlines render as `January 19`, no weekday, matching SP27. The Student Hours
  line in `survey/contact.md` is *not* in the calendar and is not updated per
  term; it still reads the Spring 2027 hours.
- The calendar's `no_class` ranges are the only source of break rows. A survey
  scaffold for a term whose calendar lacks its break has one more class week
  than the template has rows, so `schedule.py` warns about a blank week. That
  warning means "add the break to the calendar", not "write the week by hand".
- Only `2027-spring.conf` is committed. Fall 2027 onward is waiting on the
  registrar's dates.

## Publishing to the website

`./publish-web.py` generates `website/content/courses/<course>/index.md` from
the newest syllabus for each course. See that script's header for the
contract; the important half is that it **owns** those files — hand edits to
`content/courses/*/index.md` are overwritten on the next run. The website repo
is assumed at `~/git/website`; override with `WEBSITE`.

This deliberately mirrors `~/git/cv`'s `make publish`, which owns
`website/content/cv/` the same way.

## Verification

`./test.sh` runs `new.sh`, `schedule.py` and `build.sh` in a temp sandbox and
never touches the real tree. The sandbox uses fixture calendars (2032), not
`calendar/`, so exact-date assertions survive edits to a real term; the real
calendars are only checked for parsing cleanly. `--no-build` skips the PDF
smoke tests and needs no toolchain. Run it after editing any of them — and
note that with `shellcheck` installed it
also asserts the scripts stay lint-clean, so a shellcheck upgrade can fail the
suite without any change here.
