#!/usr/bin/env bash
#
# new.sh — scaffold new semester folders and syllabus files.
#
# Usage:
#   ./new.sh semester <season> <year>
#       Create a semester folder, e.g.: ./new.sh semester Fall 2027
#
#   ./new.sh syllabus <season> <year> <course> [descriptor]
#       Create a syllabus stub, e.g.:
#           ./new.sh syllabus Fall 2027 1493
#           ./new.sh syllabus Spring 2027 1103 Online
#           ./new.sh syllabus Fall 2027 1493 "MWF 8AM"
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    sed -n '/^# Usage/,/^[^#]/{ /^#/{ s/^# \?//; p } }' "$0"
    exit "${1:-0}"
}

# ---------------------------------------------------------------------------
# Normalise season → folder word and term code prefix
# ---------------------------------------------------------------------------
parse_season() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
        fall|fa)    echo "Fall FA" ;;
        spring|sp)  echo "Spring SP" ;;
        summer|su)  echo "Summer SU" ;;
        *) echo "error: unknown season '$1' (use Fall, Spring, or Summer)" >&2; exit 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------
cmd_semester() {
    [ $# -eq 2 ] || { echo "usage: ./new.sh semester <season> <year>" >&2; exit 1; }
    local season_raw="$1" year="$2"

    [[ "$year" =~ ^[0-9]{4}$ ]] || { echo "error: year must be four digits (e.g. 2027)" >&2; exit 1; }

    read -r season_word _ <<< "$(parse_season "$season_raw")"
    local folder="$ROOT/$year - $season_word"

    if [ -d "$folder" ]; then
        echo "already exists: $year - $season_word"
    else
        mkdir "$folder"
        echo "created: $year - $season_word"
    fi
}

cmd_syllabus() {
    [ $# -ge 3 ] || { echo "usage: ./new.sh syllabus <season> <year> <course> [descriptor]" >&2; exit 1; }
    local season_raw="$1" year="$2" course="$3" descriptor="${4:-}"

    [[ "$year" =~ ^[0-9]{4}$ ]] || { echo "error: year must be four digits (e.g. 2027)" >&2; exit 1; }
    [[ "$course" =~ ^[0-9]{4}$ ]] || { echo "error: course must be a four-digit number (e.g. 1493)" >&2; exit 1; }

    read -r season_word term_prefix <<< "$(parse_season "$season_raw")"
    local yy="${year: -2}"
    local term="${term_prefix}${yy}"           # e.g. FA27
    local folder="$ROOT/$year - $season_word"
    local base="$term HIST $course"
    [ -n "$descriptor" ] && base="$base $descriptor"
    local dest="$folder/$base.md"

    # Create the semester folder if it doesn't exist yet.
    if [ ! -d "$folder" ]; then
        mkdir "$folder"
        echo "created folder: $year - $season_word"
    fi

    if [ -f "$dest" ]; then
        echo "already exists: $dest" >&2; exit 1
    fi

    # Build the title line: map course number to a human-readable name.
    local course_name
    case "$course" in
        1103) course_name="Survey of American History" ;;
        1493) course_name="American History Since 1865" ;;
        2023) course_name="History of the Modern World" ;;
        3703) course_name="Oklahoma History" ;;
        3793) course_name="U.S. Environmental History" ;;
        3980) course_name="Historiography" ;;
        *)    course_name="HIST $course" ;;
    esac

    # Build the date line: include descriptor if present, otherwise plain term.
    local date_line="$season_word $year"
    [ -n "$descriptor" ] && date_line="$season_word $year - $descriptor"

    cat > "$dest" << EOF
% History $course $course_name
% $date_line
% Dr. Eberle

# Course Description

# Contact Information

Dr. Eberle\\
154 Social Sciences and Humanities\\
Student Hours: MWF 1PM-2PM or by appt.\\
Email: <jared.eberle@okstate.edu>

## Resources

- [LASSO Center](https://universitycollege.okstate.edu/lasso/): Tutoring and academic support coaches
- [OSU Counseling](https://ucs.okstate.edu): University Counseling including emergency support options
- [Victim Support Services](https://1is2many.okstate.edu/find-support/support-for-victims/index.html): Sexual violence support and reporting information.

# Required Materials

# Assignments

## Grades

| Assignment | Points |
| :--------: | :----: |
|            |        |

**Total: 100 points**

# Course Policies

# Schedule

| Week | Date | Topic | Reading |
| :--: | :--: | :----: | :-----: |
|  1   |      |        |         |
EOF

    echo "created: ${dest#"$ROOT"/}"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
[ $# -ge 1 ] || usage 1

case "$1" in
    semester) shift; cmd_semester "$@" ;;
    syllabus) shift; cmd_syllabus "$@" ;;
    -h|--help) usage 0 ;;
    *) echo "error: unknown subcommand '$1'" >&2; usage 1 ;;
esac
