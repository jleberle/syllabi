#!/usr/bin/env bash
#
# new.sh — scaffold new semester folders and syllabus files.
#
# Usage:
#   ./new.sh semester <season> <year>
#       Create a semester folder, e.g.: ./new.sh semester Fall 2027
#
#   ./new.sh syllabus <season> <year> <course> [descriptor] [options]
#       Create a syllabus stub, e.g.:
#           ./new.sh syllabus Fall 2027 1493
#           ./new.sh syllabus Fall 2027 1493 --start 2027-08-23
#           ./new.sh syllabus Spring 2027 1103 Online --start 2027-01-12
#           ./new.sh syllabus Spring 2027 1493 --start 2027-01-12 \
#               --drop-full "January 13 (Monday)" \
#               --drop-partial "January 17 (Friday)" \
#               --sixweek "February 19 (Wednesday)" \
#               --withdraw "April 4 (Friday)"
#
#       --start         First day of class (YYYY-MM-DD). Populates week headings
#                       in the schedule section. Without it, headings have no date
#                       range. In-person weeks span Monday-Friday; online (descriptor
#                       contains "online") spans Monday-Sunday.
#       --drop-full     Date of 100% tuition refund deadline (free-form text).
#       --drop-partial  Date of partial tuition refund deadline.
#       --sixweek       Date of six-week grade submission deadline.
#       --withdraw      Date of withdraw-without-penalty deadline.
#                       All four drop flags are optional; omitting any leaves a
#                       labeled placeholder in the syllabus to fill in later.
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
# Generate schedule headings via python3.
#   $1  start date (YYYY-MM-DD)
#   $2  number of weeks
#   $3  1 if online (Mon-Sun), 0 if in-person (Mon-Fri)
# ---------------------------------------------------------------------------
generate_schedule() {
    python3 - "$1" "$2" "$3" << 'PYEOF'
import sys
from datetime import date, timedelta

start     = date.fromisoformat(sys.argv[1])
weeks     = int(sys.argv[2])
is_online = sys.argv[3] == "1"

# Last day of each week: Friday for in-person, Sunday for online
end_offset = timedelta(days=6) if is_online else timedelta(days=4)

# Monday of the week that contains the start date
week_monday = start - timedelta(days=start.weekday())

def fmt(d):
    return f"{d.strftime('%B')} {d.day}"

for week in range(1, weeks + 1):
    monday = week_monday + timedelta(weeks=week - 1)
    sunday_or_friday = monday + end_offset
    print(f"## Week {week} ({fmt(monday)}-{fmt(sunday_or_friday)})")
    print()
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
    local start_date="" drop_full="" drop_partial="" sixweek="" withdraw=""
    local positional=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --start)        start_date="$2";   shift 2 ;;
            --drop-full)    drop_full="$2";    shift 2 ;;
            --drop-partial) drop_partial="$2"; shift 2 ;;
            --sixweek)      sixweek="$2";      shift 2 ;;
            --withdraw)     withdraw="$2";     shift 2 ;;
            *) positional+=("$1"); shift ;;
        esac
    done

    [ "${#positional[@]}" -ge 3 ] || {
        echo "usage: ./new.sh syllabus <season> <year> <course> [descriptor] [--start YYYY-MM-DD] [--drop-full DATE] [--drop-partial DATE] [--sixweek DATE] [--withdraw DATE]" >&2
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

    # Online if descriptor contains "online" (case-insensitive)
    local is_online=0
    echo "$descriptor" | grep -qi "online" && is_online=1

    # Drop date placeholders
    [ -n "$drop_full"    ] || drop_full="[100% refund date]"
    [ -n "$drop_partial" ] || drop_partial="[partial refund date]"
    [ -n "$sixweek"      ] || sixweek="[six-week grades date]"
    [ -n "$withdraw"     ] || withdraw="[withdraw deadline]"

    # Build schedule section
    local schedule_body
    if [ -n "$start_date" ]; then
        schedule_body="$(generate_schedule "$start_date" "$weeks" "$is_online")"
    else
        schedule_body=""
        for i in $(seq 1 "$weeks"); do
            schedule_body+="## Week $i"$'\n\n'
        done
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

#### Drops

Important deadlines for dropping the class are:

- $drop_full: 100% refund for dropped class
- $drop_partial: Partial refund for dropped class
- $sixweek: Six Week Grades
- $withdraw: Withdraw deadline

#### Accessibility Services

According to the Americans with Disabilities Act, each student with a disability is responsible for notifying the University of their disability and requesting accommodations. If you think you have a qualified disability and need accommodations, you should notify the instructor and request verification of eligibility for accommodations from Student Accessibility Services. Please advise the instructor of such disability and desired accommodations at some point before, during, or immediately after the first scheduled class period. Faculty members are obligated to respond when they receive official notice of a disability, but are under no obligation to provide retroactive accommodations. To receive services, you must submit appropriate documentation and complete an intake process during which the existence of a qualified disability is verified and reasonable accommodations are identified. Go to https://accessibility.okstate.edu for additional information.

**If you have an SAS accommodation you need to see me during office hours to discuss your accommodations and how you will use them**

#### Plagiarism/Academic Integrity

Intentional cheating on any assignment will result in formal academic integrity violation proceedings including referral to the Office of Student Conduct, and may result in a failing grade for the entire course and/or receiving a permanent notation of a violation of academic integrity on your transcript (F!) All students should be familiar with university academic integrity guidelines and procedures, including the right to appeal charges. For more information you may contact the Office of Academic Affairs, 101 Whitehurst, 405-744-5627, or visit http://academicintegrity.okstate.edu

All work completed for the course must be your own original work and only utilize assigned course materials. You are not allowed to work on assignments with others, re-submit previously used assignments, or use outside sources. Failure to comply can result in failure on the assignment or formal academic integrity inquiries.

Use of artificial intelligence programs is strictly prohibited on all assignments in the course.

# Schedule

$schedule_body
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
