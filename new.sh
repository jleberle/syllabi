#!/usr/bin/env bash
#
# new.sh — scaffold new semester folders and syllabus files.
#
# Usage:
#   ./new.sh semester <season> <year>
#       Create a semester folder, e.g.: ./new.sh semester Fall 2027
#
#   ./new.sh syllabus <season> <year> <course> [descriptor] [--start YYYY-MM-DD] [--days MWF|TR]
#       Create a syllabus stub, e.g.:
#           ./new.sh syllabus Fall 2027 1493
#           ./new.sh syllabus Fall 2027 1493 --start 2027-08-23
#           ./new.sh syllabus Fall 2027 1493 --start 2027-08-23 --days TR
#           ./new.sh syllabus Spring 2027 1103 Online --start 2027-01-12
#
#       --start  First day of class (YYYY-MM-DD). Populates dates in the
#                schedule table. Without it, the table has blank date cells.
#       --days   Class meeting pattern: MWF (default) or TR.
#                Online courses (descriptor contains "online") ignore --days
#                and show only the week-start date.
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
# Generate schedule rows via python3.
#   $1  start date (YYYY-MM-DD)
#   $2  number of weeks
#   $3  day pattern: MWF, TR, or "" (online — week-start date only)
# ---------------------------------------------------------------------------
generate_schedule() {
    python3 - "$1" "$2" "$3" << 'PYEOF'
import sys
from datetime import date, timedelta

start   = date.fromisoformat(sys.argv[1])
weeks   = int(sys.argv[2])
pattern = sys.argv[3]

if pattern == "MWF":
    offsets = [0, 2, 4]   # Mon, Wed, Fri relative to the week's Monday
elif pattern == "TR":
    offsets = [1, 3]       # Tue, Thu
else:
    offsets = []           # online: show week-start date only

# Monday of the week that contains the start date
week_monday = start - timedelta(days=start.weekday())

for week in range(1, weeks + 1):
    monday = week_monday + timedelta(weeks=week - 1)
    if offsets:
        days = [monday + timedelta(days=d) for d in offsets]
        if week == 1:
            days = [d for d in days if d >= start]
        date_str = ", ".join(f"{d.strftime('%b')} {d.day}" for d in days)
    else:
        date_str = f"{monday.strftime('%b')} {monday.day}"
    print(f"| {week:2d} | {date_str} |  |  |")
PYEOF
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
    # Separate positional args from --flags
    local start_date="" days_flag=""
    local positional=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --start) start_date="$2"; shift 2 ;;
            --days)  days_flag="$2";  shift 2 ;;
            *) positional+=("$1"); shift ;;
        esac
    done

    [ "${#positional[@]}" -ge 3 ] || {
        echo "usage: ./new.sh syllabus <season> <year> <course> [descriptor] [--start YYYY-MM-DD] [--days MWF|TR]" >&2
        exit 1
    }

    local season_raw="${positional[0]}"
    local year="${positional[1]}"
    local course="${positional[2]}"
    local descriptor="${positional[3]:-}"

    [[ "$year"   =~ ^[0-9]{4}$ ]] || { echo "error: year must be four digits (e.g. 2027)" >&2;           exit 1; }
    [[ "$course" =~ ^[0-9]{4}$ ]] || { echo "error: course must be a four-digit number (e.g. 1493)" >&2; exit 1; }

    if [ -n "$start_date" ]; then
        [[ "$start_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || {
            echo "error: --start must be YYYY-MM-DD (e.g. 2027-08-23)" >&2; exit 1
        }
    fi

    if [ -n "$days_flag" ]; then
        case "$days_flag" in
            MWF|TR) ;;
            *) echo "error: --days must be MWF or TR" >&2; exit 1 ;;
        esac
    fi

    read -r season_word term_prefix <<< "$(parse_season "$season_raw")"
    local yy="${year: -2}"
    local term="${term_prefix}${yy}"
    local folder="$ROOT/$year - $season_word"
    local base="$term HIST $course"
    [ -n "$descriptor" ] && base="$base $descriptor"
    local dest="$folder/$base.md"

    if [ ! -d "$folder" ]; then
        mkdir "$folder"
        echo "created folder: $year - $season_word"
    fi

    if [ -f "$dest" ]; then
        echo "already exists: $dest" >&2; exit 1
    fi

    # Course title lookup
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

    local date_line="$season_word $year"
    [ -n "$descriptor" ] && date_line="$season_word $year - $descriptor"

    # Weeks: 8 for Summer, 16 for Fall/Spring
    local weeks=16
    [ "$season_word" = "Summer" ] && weeks=8

    # Day pattern: online courses get week-start dates only; others default to MWF
    local is_online=0
    echo "$descriptor" | grep -qi "online" && is_online=1

    local days_pattern
    if [ "$is_online" -eq 1 ]; then
        days_pattern=""
    elif [ -n "$days_flag" ]; then
        days_pattern="$days_flag"
    else
        days_pattern="MWF"
    fi

    # Build schedule rows
    local schedule_rows
    if [ -n "$start_date" ]; then
        schedule_rows="$(generate_schedule "$start_date" "$weeks" "$days_pattern")"
    else
        schedule_rows=""
        for i in $(seq 1 "$weeks"); do
            schedule_rows+="$(printf '| %2d |  |  |  |' "$i")"$'\n'
        done
        schedule_rows="${schedule_rows%$'\n'}"
    fi

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
$schedule_rows
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
