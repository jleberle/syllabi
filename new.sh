#!/usr/bin/env bash
#
# new.sh — scaffold new semester folders and syllabus files.
#
# Usage:
#   ./new.sh semester <season> <year>
#       Create a semester folder, e.g.: ./new.sh semester Fall 2027
#
#   ./new.sh calendar <season> <year>
#       Create calendar/<year>-<season>.conf, a blank term calendar to fill in
#       from the registrar's dates. Do this once per term; every syllabus for
#       the term then picks up the same dates.
#
#   ./new.sh syllabus <season> <year> <course> [descriptor] [options]
#       Create a syllabus stub, e.g.:
#           ./new.sh syllabus Fall 2027 1493
#           ./new.sh syllabus Fall 2027 3703
#           ./new.sh syllabus Spring 2027 1103 Online
#           ./new.sh syllabus Fall 2027 1493 --start 2027-08-23 \
#               --drop-full "August 31" --withdraw "November 5"
#
#       Course type picks the template: survey (course number below 3000),
#       upper (3000 and up), or online (descriptor contains "online"). --type
#       overrides the guess.
#
#       Dates come from the term calendar when calendar/<year>-<season>.conf
#       exists: start of class, number of weeks, extra breaks, and all four
#       deadlines. Any flag below overrides it; without a calendar, deadlines
#       the flags don't supply are left as placeholders. The standard breaks
#       (Spring: MLK Day, the week of St. Patrick's Day; Fall: Labor Day, the
#       week of Thanksgiving) need no calendar, only a start date. They come
#       from rules, so new.sh lists each one it placed for you to verify.
#
#       --type          survey | upper | online.
#       --start         First day of class (YYYY-MM-DD). Weeks span Monday-Friday,
#                       or Monday-Sunday for online.
#       --drop-full     Date of 100% tuition refund deadline (free-form text).
#       --drop-partial  Date of partial tuition refund deadline.
#       --sixweek       Date of six-week grade submission deadline. A summer
#                       syllabus omits that line unless this or the calendar gives
#                       a date, since an 8-week term has no six-week grades.
#       --withdraw      Date of withdraw-without-penalty deadline.
#       --withdraw-wf   Date of the assigned W or F withdrawal deadline, which
#                       ends the petition period (survey syllabi mention it).
#
# Syllabus content comes from the templates/ folder, not this script:
#
#   templates/skeleton-<type>.md     document outline for each course type
#   templates/common/<name>.md       boilerplate shared by every type
#   templates/<type>/<name>.md       overrides for one type (survey, upper, online)
#   templates/courses/<course>/      content for one course (description,
#                                    textbook, weekly schedule rows, ...)
#
# A skeleton line of the form "{{include name}}" is replaced with the contents
# of templates/<type>/name.md if it exists, else templates/common/name.md.
# "{{include-course name}}" pulls templates/courses/<course>/name.md instead,
# and becomes a [placeholder] for a course that has none. After includes are
# expanded, {{course}}, {{course_name}}, {{date_line}}, {{drop_full}},
# {{drop_partial}}, {{sixweek}}, {{withdraw}}, {{withdraw_wf}}, and {{schedule}} are
# substituted. Edit the template files to change boilerplate; no script
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
# Render a skeleton template, expanding include lines.
#   $1  skeleton file
#   $2  course type (survey | upper | online)
#   $3  course number
# "{{include <name>}}": templates/<type>/<name>.md wins over
# templates/common/<name>.md.
# "{{include-course <name>}}": templates/courses/<course>/<name>.md, or a
# [placeholder] when that course has no such file -- never another course's
# content, which would put the wrong description into a syllabus.
# ---------------------------------------------------------------------------
render_skeleton() {
    local skeleton="$1" type="$2" course="$3"
    local tpl_dir="$ROOT/templates"
    local out="" line name snippet
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^\{\{include[[:space:]]+([A-Za-z0-9_-]+)\}\}$ ]]; then
            name="${BASH_REMATCH[1]}"
            if [ -f "$tpl_dir/$type/$name.md" ]; then
                snippet="$tpl_dir/$type/$name.md"
            elif [ -f "$tpl_dir/common/$name.md" ]; then
                snippet="$tpl_dir/common/$name.md"
            else
                echo "error: snippet '$name.md' not found in templates/$type/ or templates/common/" >&2
                return 1
            fi
            out+="$(cat "$snippet")"$'\n'
        elif [[ "$line" =~ ^\{\{include-course[[:space:]]+([A-Za-z0-9_-]+)\}\}$ ]]; then
            name="${BASH_REMATCH[1]}"
            snippet="$tpl_dir/courses/$course/$name.md"
            if [ -f "$snippet" ]; then
                out+="$(cat "$snippet")"$'\n'
            else
                out+="[${name//-/ } for HIST $course]"$'\n'
            fi
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

cmd_calendar() {
    [ $# -eq 2 ] || { echo "usage: ./new.sh calendar <season> <year>" >&2; exit 1; }
    local year="$2" season_out season_word
    [[ "$year" =~ ^[0-9]{4}$ ]] || { echo "error: year must be four digits (e.g. 2027)" >&2; exit 1; }
    season_out="$(parse_season "$1")"
    read -r season_word _ <<< "$season_out"
    command -v python3 >/dev/null 2>&1 || { echo "error: python3 not found in PATH" >&2; exit 1; }

    local dest
    dest="$ROOT/calendar/$year-$(tr '[:upper:]' '[:lower:]' <<< "$season_word").conf"
    [ ! -e "$dest" ] || { echo "already exists: ${dest#"$ROOT"/}" >&2; exit 1; }
    mkdir -p "$ROOT/calendar"
    python3 "$ROOT/schedule.py" stub "$season_word" "$year" > "$dest"
    echo "created: ${dest#"$ROOT"/} (fill in the dates from the registrar's calendar)"
}

cmd_syllabus() {
    # Separate positional args from --flags
    local start_date="" drop_full="" drop_partial="" sixweek="" withdraw="" withdraw_wf="" type=""
    local positional=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --type)         type="${2:?--type requires survey, upper, or online}"; shift 2 ;;
            --start)        start_date="${2:?--start requires a date}";          shift 2 ;;
            --drop-full)    drop_full="${2:?--drop-full requires a date}";       shift 2 ;;
            --drop-partial) drop_partial="${2:?--drop-partial requires a date}"; shift 2 ;;
            --sixweek)      sixweek="${2:?--sixweek requires a date}";           shift 2 ;;
            --withdraw)     withdraw="${2:?--withdraw requires a date}";         shift 2 ;;
            --withdraw-wf)  withdraw_wf="${2:?--withdraw-wf requires a date}";   shift 2 ;;
            *) positional+=("$1"); shift ;;
        esac
    done

    [ "${#positional[@]}" -ge 3 ] || {
        echo "usage: ./new.sh syllabus <season> <year> <course> [descriptor] [--type survey|upper|online] [--start YYYY-MM-DD] [--drop-full DATE] [--drop-partial DATE] [--sixweek DATE] [--withdraw DATE] [--withdraw-wf DATE]" >&2
        exit 1
    }

    local season_raw="${positional[0]}"
    local year="${positional[1]}"
    local course="${positional[2]}"
    local descriptor="${positional[3]:-}"

    [[ "$year"   =~ ^[0-9]{4}$ ]] || { echo "error: year must be four digits (e.g. 2027)" >&2;           exit 1; }
    [[ "$course" =~ ^[0-9]{4}$ ]] || { echo "error: course must be a four-digit number (e.g. 1493)" >&2; exit 1; }
    # The descriptor becomes part of the output filename, joined onto
    # "$term HIST $course " with no separator validation. A '/' would be
    # interpreted as a path separator by the final write, failing late with
    # a raw ENOENT and leaving an already-created semester folder behind.
    [[ "$descriptor" != */* ]] || { echo "error: descriptor cannot contain '/' (got: '$descriptor')" >&2; exit 1; }

    # Course type: an explicit --type, else online by descriptor, else survey
    # below the 3000 level and upper-division above it.
    if [ -z "$type" ]; then
        if echo "$descriptor" | grep -qi "online"; then type="online"
        elif [ "$course" -lt 3000 ]; then type="survey"
        else type="upper"
        fi
    fi
    case "$type" in
        survey|upper|online) ;;
        *) echo "error: --type must be survey, upper, or online (got: '$type')" >&2; exit 1 ;;
    esac

    command -v python3 >/dev/null 2>&1 || {
        echo "error: python3 not found in PATH (needed for schedule generation)" >&2; exit 1
    }

    if [ -n "$start_date" ]; then
        [[ "$start_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || {
            echo "error: --start must be YYYY-MM-DD (e.g. 2027-08-23)" >&2; exit 1
        }
        # The regex only checks shape; reject impossible dates (e.g. 2027-13-40,
        # 2027-02-30) here so the user gets a clean error instead of a Python
        # traceback from schedule.py later.
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

    # Weeks when no calendar says otherwise: 8 for Summer, 17 for Fall/Spring
    # (includes finals week). A calendar's `finals` date replaces this.
    local weeks=17
    [ "$season_word" = "Summer" ] && weeks=8

    # The term calendar fills in whatever the flags did not supply.
    local cal_file cal_args=() cal_out key val
    cal_file="$ROOT/calendar/$year-$(tr '[:upper:]' '[:lower:]' <<< "$season_word").conf"
    if [ -f "$cal_file" ]; then
        cal_out="$(python3 "$ROOT/schedule.py" values "$cal_file")" || exit 1
        while IFS='=' read -r key val; do
            case "$key" in
                start)        [ -n "$start_date" ]   || start_date="$val" ;;
                drop_full)    [ -n "$drop_full" ]    || drop_full="$val" ;;
                drop_partial) [ -n "$drop_partial" ] || drop_partial="$val" ;;
                sixweek)      [ -n "$sixweek" ]      || sixweek="$val" ;;
                withdraw)     [ -n "$withdraw" ]     || withdraw="$val" ;;
                withdraw_wf)  [ -n "$withdraw_wf" ]  || withdraw_wf="$val" ;;
            esac
        done <<< "$cal_out"
        cal_args=(--cal "$cal_file")
    else
        echo "note: no calendar/${cal_file##*/}, so dates come from flags only (./new.sh calendar $season_word $year creates one)" >&2
    fi

    if [ -z "$start_date" ]; then
        echo "note: no start date, so the schedule has no dates and the standard breaks (MLK Day, Spring Break, Labor Day, Thanksgiving) are not placed; add a calendar or pass --start" >&2
    fi

    # An 8-week summer term has no six-week grades, so with no date supplied the
    # line is removed instead of left as a placeholder to delete by hand.
    local omit_sixweek=0
    [ "$season_word" = "Summer" ] && [ -z "$sixweek" ] && omit_sixweek=1

    # Drop date placeholders
    [ -n "$drop_full"    ] || drop_full="[100% refund date]"
    [ -n "$drop_partial" ] || drop_partial="[partial refund date]"
    [ -n "$sixweek"      ] || sixweek="[six-week grades date]"
    [ -n "$withdraw"     ] || withdraw="[withdraw deadline]"
    [ -n "$withdraw_wf"  ] || withdraw_wf="[W or F deadline]"

    # Build schedule section: a table of weekly rows for survey courses, week
    # headings for the others.
    local sched_args=(--weeks "$weeks" --season "$season_word") schedule_body
    [ -z "$start_date" ] || sched_args+=(--start "$start_date")
    if [ "$type" = "survey" ]; then
        local missing="" part
        for part in description learning-outcomes textbook schedule; do
            [ -f "$ROOT/templates/courses/$course/$part.md" ] || missing+=" $part"
        done
        [ -z "$missing" ] || echo "note: templates/courses/$course/ has no:$missing (left as placeholders or blank rows)" >&2
        schedule_body="$(python3 "$ROOT/schedule.py" table "${sched_args[@]}" \
            ${cal_args[@]+"${cal_args[@]}"} --rows "$ROOT/templates/courses/$course/schedule.md")"
    else
        [ "$type" != "online" ] || sched_args+=(--online)
        schedule_body="$(python3 "$ROOT/schedule.py" headings "${sched_args[@]}" \
            ${cal_args[@]+"${cal_args[@]}"})"
    fi

    local skeleton="$ROOT/templates/skeleton-$type.md"
    [ -f "$skeleton" ] || { echo "error: skeleton not found: $skeleton" >&2; exit 1; }

    local content
    content="$(render_skeleton "$skeleton" "$type" "$course")"

    if [ "$omit_sixweek" -eq 1 ]; then
        content="$(grep -vF '{{sixweek}}' <<< "$content")"
    fi

    subst content '{{course}}'       "$course"
    subst content '{{course_name}}'  "$course_name"
    subst content '{{date_line}}'    "$date_line"
    subst content '{{drop_full}}'    "$drop_full"
    subst content '{{drop_partial}}' "$drop_partial"
    subst content '{{sixweek}}'      "$sixweek"
    subst content '{{withdraw}}'     "$withdraw"
    subst content '{{withdraw_wf}}'  "$withdraw_wf"
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
    calendar) shift; cmd_calendar "$@" ;;
    syllabus) shift; cmd_syllabus "$@" ;;
    -h|--help) usage 0 ;;
    *) echo "error: unknown subcommand '$1'" >&2; usage 1 ;;
esac
