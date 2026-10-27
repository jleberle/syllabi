# Syllabi

Course syllabi for Oklahoma State University History courses. Each syllabus is
written in Markdown and compiled to a web-optimized PDF via pandoc and a shared
LaTeX template.

## Prerequisites

- bash ≥ 4.3 — `build.sh` uses `wait -n`; macOS system bash is 3.2, so
  `brew install bash`
- [pandoc](https://pandoc.org) — Markdown → PDF via LaTeX
- [tectonic](https://tectonic-typesetting.github.io) — self-contained LaTeX
  engine; downloads the packages the template needs on first run and caches
  them, so no TeX distribution or package management is required
- [Ghostscript](https://www.ghostscript.com) (`gs`) — image compression
- [qpdf](https://qpdf.sourceforge.io) — linearization for fast web viewing

Install on macOS:

```
brew install pandoc tectonic ghostscript qpdf
```

The first build needs network access while tectonic populates its package
cache; subsequent builds run offline.

Last verified working with:

| Tool       | Version |
| :--------- | :------ |
| bash       | 5.3.15  |
| pandoc     | 3.10.1  |
| tectonic   | 0.17.0  |
| ghostscript| 10.07.1 |
| qpdf       | 12.3.2  |

None of these are hard-pinned — `brew install` always takes the latest. This
table is a known-good baseline: if a future rebuild renders differently than
expected, compare against these versions first. tectonic in particular ties
its LaTeX package bundle to its own release, so a newer tectonic is the most
likely source of any visual drift.

## Repository layout

```
syllabi/
├── YYYY - Season/          semester folders (e.g. "2026 - Spring")
│   └── TTNN HIST NNNN.md   syllabus source files (see naming convention below)
├── Supplemental/           non-syllabus handouts, also named with term prefixes
├── PDFs/                   compiled PDFs — mirrors semester folder layout (git-ignored)
├── calendar/               one file per term: start, finals, deadlines, holidays
├── templates/              boilerplate used by new.sh when scaffolding syllabi
│   ├── skeleton-survey.md  document outline per course type (survey, upper, online)
│   ├── skeleton-upper.md
│   ├── skeleton-online.md
│   ├── common/             policy/contact snippets shared by every type
│   ├── survey/             survey overrides (SP27 wording)
│   ├── upper/              upper-division overrides (contact info, class conduct)
│   ├── online/             online overrides (contact info, delivery note, …)
│   └── courses/<course>/   content for one course (description, textbook, weekly rows)
├── syllabus.tex            shared pandoc/LaTeX template
├── osulogo.pdf             OSU brand mark (vector) used in the template header
├── osulogo.svg             SVG source for osulogo.pdf — official OSU brand mark
│                           (Wikimedia Commons, original colors #FE5C00/#231F20)
├── build.sh                build script
├── new.sh                  scaffold script for new semesters and syllabi
├── schedule.py             term calendars and schedule generation (used by new.sh)
└── test.sh                 regression tests for build.sh, new.sh and schedule.py
```

## File naming convention

Syllabus files follow the pattern:

```
{TERM}{YY} HIST {COURSE}[ descriptor].md
```

| Part         | Values                              | Example       |
| :----------- | :---------------------------------- | :------------ |
| `TERM`       | `FA` (Fall), `SP` (Spring), `SU` (Summer) | `SP`    |
| `YY`         | two-digit year                      | `26`          |
| `HIST`       | department prefix, always present   | `HIST`        |
| `COURSE`     | four-digit course number            | `1493`        |
| `descriptor` | optional disambiguator              | `Online`, `(MWF)` |

Examples: `SP26 HIST 1493.md`, `FA25 HIST 1493.md`, `SU26 HIST 1103 Online.md`

Other `.md` files in semester folders (supplementary handouts, policy addenda,
revised schedules) are ignored by the build script because they do not start
with a term prefix.

## Building PDFs

```bash
# Build everything changed since the last run
./build.sh

# Rebuild a single semester
./build.sh "2026 - Spring"

# Build specific files
./build.sh "2026 - Spring/SP26 HIST 1493.md"

# Force-rebuild everything
./build.sh --force

# Delete all compiled PDFs
./build.sh clean
```

PDFs are written to `PDFs/` mirroring the semester folder structure, e.g.
`PDFs/2026 - Spring/SP26 HIST 1493.pdf`.

## Adding a new semester

Use `new.sh` to create correctly named folders and stub files. Once per term,
record the registrar's dates; after that every syllabus for the term needs no
date flags:

```bash
# Once per term: create calendar/2027-fall.conf, then fill it in
./new.sh calendar Fall 2027

# Then one command per course
./new.sh syllabus Fall 2027 1493      # survey
./new.sh syllabus Fall 2027 3703      # upper division
./new.sh syllabus Fall 2027 1103 Online
```

Season names and abbreviations are accepted interchangeably (`Fall`, `fall`,
`FA`, `fa`).

### Course types

| Type    | Chosen when                         | Template                        |
| :------ | :---------------------------------- | :------------------------------ |
| survey  | course number below 3000            | `templates/skeleton-survey.md`  |
| upper   | course number 3000 or above         | `templates/skeleton-upper.md`   |
| online  | descriptor contains "online"        | `templates/skeleton-online.md`  |

`--type survey|upper|online` overrides the guess (for example an online
upper-division course whose descriptor does not say "Online").

The **survey** template is the Spring 2027 HIST 1493 syllabus. A scaffold of
`Spring 2027 1493` reproduces it, and any other term differs only in its dates
and a `[student hours]` placeholder to fill in each term. The template does not
follow later hand edits to SP27: to adopt them, diff a fresh scaffold against
the edited syllabus and carry the differences into `templates/` (see
`CLAUDE.md`). A survey course other than 1493 has no description,
learning outcomes, textbook, or weekly rows of its own yet, so those come out
as `[placeholders]` and blank rows rather than 1493's content — add them under
`templates/courses/<course>/` to make them the default for that course.

### Term calendars

`calendar/<year>-<season>.conf` holds the dates that change every year:

```
start        = 2027-08-23
finals       = 2027-12-13     # any day in finals week; sets the week count
drop_full    = 2027-08-31
drop_partial = 2027-09-03
sixweek      = 2027-10-05
withdraw     = 2027-11-05
withdraw_wf  = 2027-11-29     # assigned W or F deadline; ends the petition period
no_class     = 2027-10-18..2027-10-19 | Fall Break   # anything beyond the standard breaks
```

Dates are `YYYY-MM-DD`; `no_class` takes one date or `START..END` and a label,
and may repeat. From the calendar `new.sh` fills in the drop deadlines and
writes the schedule: week ranges, the week count, a break row for any week with
no class Monday through Friday, and a "No class" note for a partial week. If a
weekly row schedules something on a no-class day, `new.sh` warns about it.

**Standard breaks** need no entry (and no calendar at all, only a start date):

| Season | Breaks                                                              |
| :----- | :------------------------------------------------------------------ |
| Spring | MLK Day (third Monday of January); Spring Break, the Monday–Friday week of St. Patrick's Day (March 17) |
| Fall   | Labor Day (first Monday of September); Thanksgiving Break, the week of the fourth Thursday of November |
| Summer | none                                                                |

MLK Day, Labor Day and Thanksgiving follow fixed holidays, so they are simply
placed. Spring Break is the registrar's choice and could shift, so when it comes
from the rule rather than a calendar entry, `new.sh` prints its dates as a note
to verify. With no start date there is nothing to place a break on, and `new.sh`
says so.

A `no_class` entry on the same day keeps its own label. If a year's registrar
calendar departs from the rules, put `standard_breaks = off` in that term's
calendar and list its breaks with `no_class`. The rules were checked against the
registrar's calendars: Spring Break is the Monday between March 13 and 19, so
a weekend March 17 (2018, 2019, 2024) rolls to the following week.

`./new.sh calendar` writes a blank file with the registrar's fields left empty.
**Deadlines are never guessed**: a blank field leaves a placeholder in the
syllabus (except summer's six-week grades, which an 8-week term does not have:
that line is omitted unless a date is given). A typo such as `withdrawl =` or a date like `8/23/2027` is an error
rather than a silently missing deadline, and a deadline that falls outside the
term (a wrong-year typo) produces a warning.

Flags override the calendar for one syllabus, and work with no calendar at all:

```bash
./new.sh syllabus Fall 2027 3703 --start 2027-08-23 \
    --drop-full "August 31" --drop-partial "September 3" \
    --sixweek "October 5" --withdraw "November 5"
```

The survey schedule is a table; the other types get `## Week N (Month D-Month D)`
headings. In-person weeks span Monday–Friday and online weeks Monday–Sunday.
With no calendar, Fall and Spring generate 17 weeks (including finals week) and
Summer 8.

### Stub content lives in templates/

All boilerplate comes from the `templates/` folder, not from `new.sh` itself —
edit those files to change what future stubs contain (existing syllabi are
never touched):

- `templates/skeleton-<type>.md` is the document outline for each course type
  (section order, headings, grade tables).
- A skeleton line of the form `{{include name}}` is replaced with the contents
  of a snippet file: `templates/<type>/name.md` if it exists for the course
  type, otherwise `templates/common/name.md`. Shared policies (academic
  integrity, drops, …) live in `common/`; a type's own wording (contact info,
  class conduct, the online delivery note) lives in `survey/`, `upper/` or
  `online/`. To give a shared snippet a type-specific version, just add a file
  with the same name there — no script changes needed.
- `{{include-course name}}` is replaced with
  `templates/courses/<course>/name.md`, or a `[placeholder]` if that course has
  none. The survey skeleton uses `description`, `learning-outcomes`,
  `textbook`, and `schedule` (the weekly rows: `| events | topic | textbook |`,
  one per class week with the finals-week row last).
- `{{drop_full}}`, `{{drop_partial}}`, `{{sixweek}}`, `{{withdraw}}`,
  `{{course}}`, `{{course_name}}`, `{{date_line}}`, and `{{schedule}}` are
  substituted everywhere after includes are expanded, so snippets can also
  reference the calendar dates.

Then edit the generated file and compile:

```bash
./build.sh "2027 - Fall"
```

## Template

`syllabus.tex` is a pandoc template using the OSU color palette (orange
headings, serif body). To change layout or branding, edit that file — changes
apply to all syllabi on the next build.

## Testing

`test.sh` exercises `new.sh`, `schedule.py` and `build.sh` in a throwaway
sandbox (a temp copy of the scripts and templates, with fixture calendars), so
it never touches the real tree:

```bash
./test.sh              # full suite, including a build smoke test
./test.sh --no-build   # skip the build tests (fast; no PDF toolchain needed)
```

It covers scaffolding and input validation, course types, term calendars
(drop dates, break and holiday rows, flag overrides, malformed files), schedule
generation (week ranges and counts), literal field substitution, calendar-date
rejection, that the committed calendars parse cleanly, and the
build pipeline (PDF output, incremental skips, per-file failure isolation,
the term-prefix filter, and path handling). With `shellcheck` installed it
also asserts the scripts stay lint-clean. Run it after editing either script.

### Pre-commit hook

`hooks/pre-commit` runs `./test.sh --no-build` automatically, but only for
commits that touch `build.sh`, `new.sh`, `schedule.py`, `test.sh`,
`syllabus.tex`, `templates/`, or `calendar/` — ordinary syllabus content
commits are unaffected. Git doesn't
track `.git/hooks/`, so enable it once per clone:

```bash
git config core.hooksPath hooks
```
