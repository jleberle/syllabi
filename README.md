# Syllabi

Course syllabi for Oklahoma State University History courses. Each syllabus is
written in Markdown and compiled to a web-optimized PDF via pandoc and a shared
LaTeX template.

## Prerequisites

- [pandoc](https://pandoc.org) — Markdown → PDF via LaTeX
- A TeX distribution — [MacTeX](https://tug.org/mactex/) (macOS) or TeX Live
- [ocrmypdf](https://ocrmypdf.readthedocs.io) — post-processing: OCR text layer,
  compression, linearization

Install on macOS:

```
brew install pandoc ocrmypdf
brew install --cask mactex
```

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

# Syllabus with no schedule dates (placeholder rows)
./new.sh syllabus Fall 2027 1493

# Syllabus with auto-populated schedule — defaults to MWF
./new.sh syllabus Fall 2027 1493 --start 2027-08-23

# TR course
./new.sh syllabus Spring 2027 1493 --start 2027-01-12 --days TR

# Online course — descriptor containing "online" suppresses day columns,
# showing only the week-start date
./new.sh syllabus Spring 2027 1103 Online --start 2027-01-12
```

Season names and abbreviations are accepted interchangeably (`Fall`, `fall`,
`FA`, `fa`). The stub includes the pandoc title block, standard contact info
and resources, and placeholder sections for description, materials, assignments,
policies, and schedule. Fall and Spring semesters generate 16 weeks; Summer
generates 8.

Then edit the generated file and compile:

```bash
./build.sh "2027 - Fall"
```

## Template

`syllabus.tex` is a pandoc template using the OSU color palette (orange
headings, serif body). To change layout or branding, edit that file — changes
apply to all syllabi on the next build.
