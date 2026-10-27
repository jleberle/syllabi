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

To carry hand edits from a taught syllabus back into the template, scaffold the
same term and course in a scratch copy and `diff` it against the edited file.
Everything that differs is either an edit to merge (into the skeleton or the
matching `survey/` snippet) or something term-specific that must become a
placeholder instead (Student Hours; the petition-period date is
`{{withdraw_wf}}`, from the calendar's `withdraw_wf`). The last merge was
2026-10-27; after it the only difference from SP27 was the Student Hours line.

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
likewise overrides `academic-integrity`, `grade-disputes`, `incomplete-grades`,
`class-conduct`, `resources` and the reporting notice with SP27's wording. Those are survey-only; `common/` is unchanged and still
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

- **Deadlines are never inferred.** A blank key leaves a `[placeholder]` in the
  syllabus; the registrar's dates must be typed in. Do not "helpfully" fill in a
  future term from last year's offsets: they are not constant (Spring 2026 and
  2027 withdraw deadlines are 88 days after the start, Fall 2026's is 81).
  `./new.sh calendar <season> <year>` writes the blank file.
- **Breaks are inferred, by rules checked against the registrar.** Spring: MLK
  Day (third Monday of January) and Spring Break, the Monday between March 13
  and 19 (the week of St. Patrick's Day; a weekend March 17 rolls *forward*, as
  in 2018, 2019 and 2024). Fall: Labor Day (first Monday of September) and the
  week of the fourth Thursday of November (Mon-Wed "Fall Break" plus Thu-Fri
  holiday). Summer: none. They apply whenever there is a start date, calendar
  or not. Verified against the registrar's published calendars: Spring
  2018-2027 and Fall 2020-2026. Known exceptions: Spring 2021 had no Spring
  Break (scattered "Wellness Days"), and before Fall 2020 Thanksgiving was
  only Wed/Thu-Fri, so scaffolding a pre-2020 Fall gives a break week the
  registrar did not. Calendar `no_class` entries are added to the rules and win
  a day's label; `standard_breaks = off` drops the rules for a term that departs
  from them (then list that term's breaks). So an explicit second Spring Break
  `no_class` *adds* a break rather than replacing the standard one.
  Only Spring Break is echoed by `new.sh` as a "verify against the registrar"
  note (stderr), and only when it came from the rule rather than a calendar
  entry: MLK Day, Labor Day and Thanksgiving follow fixed holidays and are
  placed without comment. A scaffold with no start date says it placed no
  breaks. The user supplies start dates with `--start`; they are never inferred.
- `finals` sets the week count (start's Monday through finals' Monday). Without
  it, 17 weeks for Fall/Spring and 8 for Summer.
- Flags (`--start`, `--drop-*`) override the calendar per syllabus. Unknown keys
  and malformed dates are errors on purpose, so a typo cannot silently drop a
  deadline.
- Deadlines render as `January 19`, no weekday, matching SP27. Student Hours is
  not in the calendar: `survey/contact.md` and `upper/contact.md` carry a
  `[student hours]` placeholder to fill in per syllabus, so a stale time cannot
  carry over. (`online/contact.md` has no time slot, just "appointments via
  Zoom".)
- A survey scaffold needs exactly as many class weeks as the template has rows
  (15 plus finals). A term with an extra break the rules and calendar don't
  know about has one more class week than rows, so `schedule.py` warns about a
  blank week. That warning means "add the break to the calendar", not "write
  the week by hand".
- Committed: Spring 2027, Summer 2027, Fall 2027, Spring 2028, Summer 2028.
  The best source is the University Catalog's academic calendar
  (`catalog.okstate.edu/academic-calendar/`), which tables a whole academic
  year at once, summer included; the registrar's per-term pages lag it. **The
  2027-28 table is marked "(Pending)"** (read 2026-10-27), so Fall 2027,
  Spring 2028 and Summer 2028 may still move: recheck before the term and edit
  the file. Each file's header records the source and the date read.
- The catalog gives no six-week grade date for summer, and an 8-week term has
  none, so a summer scaffold **omits** the "Six Week Grades" line unless a date
  is supplied (`--sixweek` or a `sixweek` key). Fall and Spring still keep the
  `[six-week grades date]` placeholder when the date is missing.
- Summer holidays (Juneteenth, July 4th observed) are `no_class` entries, not
  rules, because they move around the weekday. They show on in-person summer
  schedules but not online ones, which do not list single holidays.

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
