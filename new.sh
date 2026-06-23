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
# Syllabus content comes from the templates/ folder, not this script:
#
#   templates/skeleton.md          document outline for in-person courses
#   templates/skeleton-online.md   document outline for online courses
#   templates/common/<name>.md     boilerplate shared by both formats
#   templates/inperson/<name>.md   in-person overrides (e.g. contact.md)
#   templates/online/<name>.md     online overrides
#
# A skeleton line of the form "{{include name}}" is replaced with the contents
# of templates/<variant>/name.md if it exists, else templates/common/name.md.
# After includes are expanded, {{course}}, {{course_name}}, {{date_line}},
# {{drop_full}}, {{drop_partial}}, {{sixweek}}, {{withdraw}}, and {{schedule}}
# are substituted. Edit the template files to change boilerplate; no script
# changes needed.
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
# Render a skeleton template, expanding "{{include <name>}}" lines.
#   $1  skeleton file
#   $2  variant (inperson | online)
# templates/<variant>/<name>.md wins over templates/common/<name>.md.
# ---------------------------------------------------------------------------
render_skeleton() {
    local skeleton="$1" variant="$2"
    local tpl_dir="$ROOT/templates"
    local out="" line name snippet
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^\{\{include[[:space:]]+([A-Za-z0-9_-]+)\}\}$ ]]; then
            name="${BASH_REMATCH[1]}"
            if [ -f "$tpl_dir/$variant/$name.md" ]; then
                snippet="$tpl_dir/$variant/$name.md"
            elif [ -f "$tpl_dir/common/$name.md" ]; then
                snippet="$tpl_dir/common/$name.md"
            else
                echo "error: snippet '$name.md' not found in templates/$variant/ or templates/common/" >&2
                return 1
            fi
            out+="$(cat "$snippet")"$'\n'
        else
            out+="$line"$'\n'
        fi
    done < "$skeleton"
    printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# Replace every literal occurrence of a placeholder with a value, writing the
# result back into the named variable.
#   $1  name of the variable holding the text (modified in place)
#   $2  literal placeholder to find, e.g. "{{course}}"
#   $3  literal replacement value
# Uses prefix/suffix removal rather than "${var//pat/repl}" so the replacement
# is treated as a literal string. bash >= 5.0 interprets '&' in a ${//}
# replacement as the matched text, which would turn a value like "Smith & Co."
# into the placeholder name; '\' is likewise special. This approach is immune
# to both and is portable back to bash 3.2.
# ---------------------------------------------------------------------------
subst() {
    local __var="$1" needle="$2" repl="$3"
    local hay="${!__var}" out=""
    while [[ "$hay" == *"$needle"* ]]; do
        out+="${hay%%"$needle"*}$repl"
        hay="${hay#*"$needle"}"
    done
    printf -v "$__var" '%s' "$out$hay"
}

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------
cmd_semester() {
    [ $# -eq 2 ] || { echo "usage: ./new.sh semester <season> <year>" >&2; exit 1; }
    local season_raw="$1" year="$2"

    [[ "$year" =~ ^[0-9]{4}$ ]] || { echo "error: year must be four digits (e.g. 2027)" >&2; exit 1; }

    # Capture before read: a parse_season failure inside <<< "$(...)" would
    # otherwise be masked and the script would continue with empty vars.
    local season_out
    season_out="$(parse_season "$season_raw")"
    read -r season_word _ <<< "$season_out"
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
            --start)        start_date="${2:?--start requires a date}";          shift 2 ;;
            --drop-full)    drop_full="${2:?--drop-full requires a date}";       shift 2 ;;
            --drop-partial) drop_partial="${2:?--drop-partial requires a date}"; shift 2 ;;
            --sixweek)      sixweek="${2:?--sixweek requires a date}";           shift 2 ;;
            --withdraw)     withdraw="${2:?--withdraw requires a date}";         shift 2 ;;
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
        command -v python3 >/dev/null 2>&1 || {
            echo "error: python3 not found in PATH (needed for --start schedule generation)" >&2; exit 1
        }
        # The regex only checks shape; reject impossible dates (e.g. 2027-13-40,
        # 2027-02-30) here so the user gets a clean error instead of a Python
        # traceback from generate_schedule later.
        python3 -c 'import datetime,sys; datetime.date.fromisoformat(sys.argv[1])' "$start_date" 2>/dev/null || {
            echo "error: --start is not a valid calendar date: $start_date" >&2; exit 1
        }
    fi

    # Capture before read: a parse_season failure inside <<< "$(...)" would
    # otherwise be masked and the script would continue with empty vars.
    local season_out
    season_out="$(parse_season "$season_raw")"
    read -r season_word term_prefix <<< "$season_out"
    local yy="${year: -2}"
    local term="${term_prefix}${yy}"
    local folder="$ROOT/$year - $season_word"
    local base="$term HIST $course"
    [ -n "$descriptor" ] && base="$base $descriptor"
    local dest="$folder/$base.md"

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
        *)    course_name="[Course Title]" ;;
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
        schedule_body="${schedule_body%$'\n\n'}"
    fi

    # Pick the skeleton: online courses use skeleton-online.md when present
    local variant="inperson"
    [ "$is_online" -eq 1 ] && variant="online"
    local skeleton="$ROOT/templates/skeleton.md"
    [ "$variant" = "online" ] && [ -f "$ROOT/templates/skeleton-online.md" ] \
        && skeleton="$ROOT/templates/skeleton-online.md"
    [ -f "$skeleton" ] || { echo "error: skeleton not found: $skeleton" >&2; exit 1; }

    local content
    content="$(render_skeleton "$skeleton" "$variant")"

    subst content '{{course}}'       "$course"
    subst content '{{course_name}}'  "$course_name"
    subst content '{{date_line}}'    "$date_line"
    subst content '{{drop_full}}'    "$drop_full"
    subst content '{{drop_partial}}' "$drop_partial"
    subst content '{{sixweek}}'      "$sixweek"
    subst content '{{withdraw}}'     "$withdraw"
    subst content '{{schedule}}'     "$schedule_body"

    # Create the destination folder only now, right before writing, so a
    # failure earlier (an invalid date, a missing snippet) never leaves an
    # empty semester folder behind.
    if [ ! -d "$folder" ]; then
        mkdir -p "$folder"
        echo "created folder: $year - $season_word"
    fi

    printf '%s\n' "$content" > "$dest"
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
