# Syllabi

Course syllabi for Oklahoma State University History courses. Each syllabus is
written in Markdown and compiled to a web-optimized PDF via pandoc and a shared
LaTeX template.

## Prerequisites

- bash ≥ 4.3 — `build.sh` uses `wait -n`; macOS system bash is 3.2, so
  `brew install bash`
- [pandoc](https://pandoc.org) — Markdown → PDF via LaTeX
- A TeX distribution — [BasicTeX](https://tug.org/mactex/morepackages.html)
  (minimal) or [MacTeX](https://tug.org/mactex/) (full) on macOS, or TeX Live
- [Ghostscript](https://www.ghostscript.com) (`gs`) — image compression
- [qpdf](https://qpdf.sourceforge.io) — linearization for fast web viewing

Install on macOS:

```
brew install pandoc ghostscript qpdf
brew install --cask basictex   # or: brew install --cask mactex
```

BasicTeX ships a minimal package set; install the extra packages the
template's font stack (XCharter body, LY1 encoding) needs:

```
sudo tlmgr install xstring fontaxes ly1
```

(The full MacTeX cask already includes these, so this step is only needed
with BasicTeX.)

## Repository layout

```
syllabi/
├── YYYY - Season/          semester folders (e.g. "2026 - Spring")
│   └── TTNN HIST NNNN.md   syllabus source files (see naming convention below)
├── Supplemental/           non-syllabus handouts, also named with term prefixes
├── PDFs/                   compiled PDFs — mirrors semester folder layout (git-ignored)
├── syllabus.tex            shared pandoc/LaTeX template
├── osulogo.png             OSU logo used in the template header
├── build.sh                build script
└── new.sh                  scaffold script for new semesters and syllabi
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

Use `new.sh` to create correctly named folders and stub files:

```bash
# Create a semester folder
./new.sh semester Fall 2027

# Syllabus with no dates (placeholder schedule headings and drop dates)
./new.sh syllabus Fall 2027 1493

# Syllabus with auto-populated schedule
./new.sh syllabus Fall 2027 1493 --start 2027-08-23

# Online course — "online" in descriptor gives Mon-Sun week ranges
./new.sh syllabus Spring 2027 1103 Online --start 2027-01-12

# With drop/deadline dates from the OSU academic calendar
./new.sh syllabus Spring 2027 1493 --start 2027-01-12 \
    --drop-full "January 13 (Monday)" \
    --drop-partial "January 17 (Friday)" \
    --sixweek "February 19 (Wednesday)" \
    --withdraw "April 4 (Friday)"
```

Season names and abbreviations are accepted interchangeably (`Fall`, `fall`,
`FA`, `fa`). The stub includes the pandoc title block, standard contact info
and resources, placeholder sections for description, materials, and assignments,
and the following auto-populated policy sections:

- **Drops** — four deadline dates from the OSU academic calendar. Supply them
  with `--drop-full`, `--drop-partial`, `--sixweek`, and `--withdraw`; omitting
  any flag leaves a labeled placeholder to fill in later.
- **Accessibility Services** — static boilerplate, always included.
- **Plagiarism/Academic Integrity** — static boilerplate, always included.

The schedule section uses `## Week N (Month D-Month D)` headings. In-person
weeks span Monday–Friday; online weeks span Monday–Sunday. Without `--start`
the headings are generated with no date range. Fall and Spring semesters
generate 16 weeks; Summer generates 8.

Then edit the generated file and compile:

```bash
./build.sh "2027 - Fall"
```

## Template

`syllabus.tex` is a pandoc template using the OSU color palette (orange
headings, serif body). To change layout or branding, edit that file — changes
apply to all syllabi on the next build.
