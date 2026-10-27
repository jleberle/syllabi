#!/usr/bin/env bash
#
# test.sh — regression tests for new.sh, schedule.py and build.sh.
#
# Every check runs in an isolated sandbox (a temp copy of the scripts,
# templates, LaTeX template, and logo), so the real tree is never touched.
#
# Usage:
#   ./test.sh              run all tests; build smoke tests are included when
#                          the pandoc/gs/qpdf/tectonic toolchain is installed
#   ./test.sh --no-build   skip the build smoke tests (fast; no PDF toolchain
#                          or tectonic package cache needed)
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Matches build.sh's own requirement (wait -n); test.sh also exercises build.sh.
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
    echo "error: bash >= 4.3 required, found $BASH_VERSION (on macOS: brew install bash)" >&2
    exit 1
fi

NO_BUILD=0
for arg in "$@"; do
    case "$arg" in
        --no-build) NO_BUILD=1 ;;
        -h|--help)  sed -n '/^# Usage/,/^[^#]/{ /^#/{ s/^# \?//; p } }' "$0"; exit 0 ;;
        *) echo "unknown argument: $arg (try --no-build or --help)" >&2; exit 2 ;;
    esac
done

# ---------------------------------------------------------------------------
# Tiny assertion harness
# ---------------------------------------------------------------------------
PASS=0 FAIL=0
RED='' GREEN='' DIM='' RESET=''
if [ -t 1 ]; then RED=$'\033[31m' GREEN=$'\033[32m' DIM=$'\033[2m' RESET=$'\033[0m'; fi

pass() { PASS=$((PASS + 1)); printf '  %sok%s   %s\n' "$GREEN" "$RESET" "$1"; }
fail() {
    FAIL=$((FAIL + 1))
    printf '  %sFAIL%s %s\n' "$RED" "$RESET" "$1"
    [ -n "${2:-}" ] && printf '       %s%s%s\n' "$DIM" "$2" "$RESET"
}
section() { printf '\n%s%s%s\n' "$DIM" "$1" "$RESET"; }

# Run a command; stash combined output in OUT and exit status in RC.
run() { OUT="$("$@" 2>&1)"; RC=$?; return 0; }

have_build_tools() {
    local t
    for t in pandoc gs qpdf tectonic; do
        command -v "$t" >/dev/null 2>&1 || return 1
    done
}

assert_rc()     { if [ "$RC" -eq "$1" ]; then pass "$2"; else fail "$2" "expected exit $1, got $RC — $OUT"; fi; }
assert_dir()    { if [ -d "$1" ];   then pass "$2"; else fail "$2" "missing dir: $1"; fi; }
assert_file()   { if [ -f "$1" ];   then pass "$2"; else fail "$2" "missing file: $1"; fi; }
assert_absent() { if [ ! -e "$1" ]; then pass "$2"; else fail "$2" "should not exist: $1"; fi; }
assert_eq()     { if [ "$1" = "$2" ]; then pass "$3"; else fail "$3" "expected '$1', got '$2'"; fi; }
assert_has()    { if grep -qF -- "$2" "$1" 2>/dev/null; then pass "$3"; else fail "$3" "literal not in $1: $2"; fi; }
assert_hasnt()  { if grep -qF -- "$2" "$1" 2>/dev/null; then fail "$3" "unexpected literal in $1: $2"; else pass "$3"; fi; }
assert_in()     { case "$2" in *"$1"*) pass "$3" ;; *) fail "$3" "'$1' not in output: $2" ;; esac; }

# ---------------------------------------------------------------------------
# Sandbox
# ---------------------------------------------------------------------------
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
cp "$REPO/new.sh" "$REPO/build.sh" "$REPO/schedule.py" "$REPO/syllabus.tex" "$REPO/osulogo.pdf" "$SB"/
cp -R "$REPO/templates" "$SB/templates"
# The sandbox gets fixture calendars, not the real ones: the tests assert exact
# dates, which must not change when a real term's calendar is edited.
mkdir "$SB/calendar"
cd "$SB" || exit 1
N="$SB/new.sh"
B="$SB/build.sh"

printf 'testing in sandbox %s\n' "$SB"

# ===========================================================================
section "new.sh semester"
# ===========================================================================
run "$N" semester Fall 2027
assert_rc 0 "create semester"
assert_dir "2027 - Fall" "semester folder created"
assert_in "created" "$OUT" "reports creation"

run "$N" semester fall 2027
assert_rc 0 "re-running is idempotent"
assert_in "already exists" "$OUT" "reports already-exists"

run "$N" semester FA 2027
assert_in "already exists" "$OUT" "abbreviation maps to same folder"

run "$N" semester Winter 2027
assert_rc 1 "unknown season rejected"

run "$N" semester Fall 27
assert_rc 1 "two-digit year rejected"

# ===========================================================================
section "new.sh syllabus — scaffolding & validation"
# ===========================================================================
run "$N" syllabus Fall 2027 1493 --start 2027-08-23
assert_rc 0 "create in-person syllabus"
IP="2027 - Fall/FA27 HIST 1493.md"
assert_file "$IP" "syllabus file created"
assert_has "$IP" "History 1493 American History Since 1865" "course title from lookup table"
assert_has "$IP" "Fall 2027" "date line rendered"
assert_hasnt "$IP" "{{" "no leftover {{placeholders}}"

run "$N" syllabus Fall 2027 1493 --start 2027-08-23
assert_rc 1 "duplicate file refused"
assert_in "already exists" "$OUT" "duplicate reports already-exists"

run "$N" syllabus Fall 2027 9999 --start 2027-08-23
assert_rc 0 "unknown course still scaffolds"
assert_has "2027 - Fall/FA27 HIST 9999.md" "[Course Title]" "unknown course -> placeholder title"

run "$N" syllabus Fall 2027 149
assert_rc 1 "non-four-digit course rejected"

run "$N" syllabus Fall 2027 1493 '../../escape'
assert_rc 1 "descriptor containing '/' rejected"
assert_in "cannot contain '/'" "$OUT" "clean error (no raw ENOENT) for '/' in descriptor"
assert_absent "2027 - Fall/FA27 HIST 1493 ../../escape.md" "rejected descriptor writes no file"

run "$N" syllabus Fall 2027
assert_rc 1 "too few positional args rejected"

run "$N" syllabus Fall 2027 1493 --start
assert_rc 1 "missing --start value rejected"

# ===========================================================================
section "new.sh — schedule generation (2030-08-26 is a Monday)"
# ===========================================================================
run "$N" syllabus Fall 2030 3703 --start 2030-08-26
SCHED_IP="2030 - Fall/FA30 HIST 3703.md"
assert_has "$SCHED_IP" "## Week 1 (August 26-August 30)" "in-person week spans Mon-Fri"
assert_eq 17 "$(grep -c '^## Week' "$SCHED_IP")" "Fall = 17 weeks"

run "$N" syllabus Fall 2030 1103 Online --start 2030-08-26
SCHED_ON="2030 - Fall/FA30 HIST 1103 Online.md"
assert_has "$SCHED_ON" "## Week 1 (August 26-September 1)" "online week spans Mon-Sun"
assert_has "$SCHED_ON" "A Note About Online Delivery" "online skeleton selected for online descriptor"
assert_hasnt "$IP"     "A Note About Online Delivery" "in-person skeleton omits the online note"

run "$N" syllabus Summer 2030 1103 Online --start 2030-06-02
assert_eq 8 "$(grep -c '^## Week' "2030 - Summer/SU30 HIST 1103 Online.md")" "Summer = 8 weeks"

run "$N" syllabus Fall 2030 3793 --start 2030-08-28   # Wednesday start
assert_has "2030 - Fall/FA30 HIST 3793.md" "## Week 1 (August 26-August 30)" "mid-week start snaps back to Monday"

run "$N" syllabus Spring 2030 3703
assert_rc 0 "syllabus without --start scaffolds"
NODATE="2030 - Spring/SP30 HIST 3703.md"
assert_has   "$NODATE" "## Week 1"  "no --start -> bare week heading"
assert_hasnt "$NODATE" "## Week 1 (" "no --start -> no date range"
assert_eq 17 "$(grep -c '^## Week' "$NODATE")" "no --start still produces 17 Fall weeks"

# ===========================================================================
section "new.sh — literal substitution (the & / backslash corruption fix)"
# ===========================================================================
run "$N" syllabus Fall 2031 1103 --start 2031-08-25 \
    --drop-full 'Aug 26 (A&B) 50% \ path' \
    --withdraw  'Smith & Co. deadline'
AMP="2031 - Fall/FA31 HIST 1103.md"
assert_has "$AMP" 'Aug 26 (A&B) 50% \ path' "& and backslash in --drop-full kept verbatim"
assert_has "$AMP" 'Smith & Co. deadline'    "& in --withdraw kept verbatim"
assert_hasnt "$AMP" "{{" "& value did not corrupt into a placeholder name"

run "$N" syllabus Fall 2031 2023 'A&M' --start 2031-08-25
assert_has "2031 - Fall/FA31 HIST 2023 A&M.md" "Fall 2031 - A&M" "& in descriptor/date line kept verbatim"

# ===========================================================================
section "new.sh — invalid calendar dates (clean error, no orphan folder)"
# ===========================================================================
for d in 2028-13-40 2028-02-30 2028-00-10; do
    run "$N" syllabus Spring 2028 1493 --start "$d"
    assert_rc 1 "impossible date rejected: $d"
    assert_in "not a valid calendar date" "$OUT" "clean error (no traceback) for $d"
done
assert_absent "2028 - Spring" "failed scaffold leaves no orphan semester folder"

run "$N" syllabus Spring 2028 1493 --start 2028-01-13
assert_rc 0 "valid date still works after rejections"

# ===========================================================================
section "new.sh — course types"
# ===========================================================================
SURVEY="2027 - Fall/FA27 HIST 1493.md"      # created above: 1493 is below 3000
assert_has   "$SURVEY" "Final Exam Replacement"      "course number < 3000 -> survey template"
assert_has   "$SURVEY" "history is an argument about evidence" "1493 course content filled in"
assert_hasnt "$SURVEY" "[description for HIST"       "1493 has no course-content placeholders"
UPPER="2030 - Fall/FA30 HIST 3703.md"
assert_hasnt "$UPPER"  "Final Exam Replacement"      "course number >= 3000 -> upper-division template"
assert_has   "$SURVEY" "Care Report"                 "survey: its own resources list"
assert_hasnt "$UPPER"  "Care Report"                 "upper: still the common resources list"
assert_has   "$SURVEY" "committed to the maintenance of the highest standards" "survey: its own academic integrity wording"
assert_hasnt "$UPPER"  "committed to the maintenance of the highest standards" "upper: still the common academic integrity wording"
assert_has   "$UPPER"  "# Course Policies"           "upper-division skeleton used"

run "$N" syllabus Fall 2027 1103 Online
assert_has "2027 - Fall/FA27 HIST 1103 Online.md" "A Note About Online Delivery" "descriptor 'online' -> online template"

run "$N" syllabus Fall 2027 3703 Hybrid --type online
assert_rc 0 "--type online accepted"
assert_has "2027 - Fall/FA27 HIST 3703 Hybrid.md" "A Note About Online Delivery" "--type overrides the guess"

run "$N" syllabus Fall 2027 1103 Honors --type upper
assert_hasnt "2027 - Fall/FA27 HIST 1103 Honors.md" "Final Exam Replacement" "--type upper on a survey number"

run "$N" syllabus Fall 2027 2023 --type bogus
assert_rc 1 "unknown --type rejected"
assert_in "--type must be" "$OUT" "clean error for unknown --type"
assert_absent "2027 - Fall/FA27 HIST 2023.md" "rejected --type writes no file"

run "$N" syllabus Fall 2027 2023
assert_rc 0 "survey course with no course content still scaffolds"
assert_has "2027 - Fall/FA27 HIST 2023.md" "[description for HIST 2023]" "missing course content -> placeholder"
assert_in "has no: description" "$OUT" "missing course content is reported"
assert_hasnt "2027 - Fall/FA27 HIST 2023.md" "Reconstruction" "another course's content is never borrowed"

# ===========================================================================
section "new.sh — term calendar (fixture: 2032 Spring, Monday start 2032-01-12)"
# ===========================================================================
cat > calendar/2032-spring.conf <<'CAL'
# fixture
start        = 2032-01-12
finals       = 2032-05-03     # inline comment
drop_full    = 2032-01-20
drop_partial = 2032-01-23
sixweek      = 2032-02-25
withdraw     = 2032-04-09
withdraw_wf  = 2032-04-23
no_class     = 2032-01-19 | MLK Day
no_class     = 2032-03-15..2032-03-19 | Spring Break
no_class     = 2032-04-07..2032-04-09 | Test Recess
CAL
run "$N" syllabus Spring 2032 1493
assert_rc 0 "scaffold from a calendar with no date flags"
CAL="2032 - Spring/SP32 HIST 1493.md"
assert_hasnt "$CAL" "{{" "no leftover placeholders"
assert_has   "$CAL" "- January 20: 100% refund for dropped class" "drop_full from calendar, as 'Month D'"
assert_has   "$CAL" "- April 9: Withdraw deadline"                 "withdraw from calendar"
assert_has   "$CAL" "(through April 23) are the petition period" "the W-or-F deadline fills the petition-period note"
assert_eq 17 "$(grep -cE '^\| [0-9]+ \| ' "$CAL")" "week count comes from start..finals"
assert_has   "$CAL" "| 1 | Jan 12–16 |"                            "week 1 dates"
assert_has   "$CAL" "| 2 | Jan 19–23 | Mon:&nbsp;No class (MLK Day); **Fri:&nbsp;Source Workshop 1" "single no-class day noted ahead of the week's events"
assert_has   "$CAL" "| 10 | Mar 15–19 | No class | Spring Break |  |" "a fully-off week becomes a break row"
assert_has   "$CAL" "| 11 | Mar 22–26 | **Fri:&nbsp;Source Workshop 5" "weekly rows resume after the break instead of shifting"
assert_has   "$CAL" "Wed–Fri:&nbsp;No class (Test Recess)"         "partial week noted as a day range"
assert_has   "$CAL" "| 13 | Apr 5–9 |"                             "week 13 dates"
assert_has   "$CAL" "| 17 | May 3–7 | **Final Exam**"               "finals row lands on the last week"
assert_in "no-class day (Test Recess)" "$OUT" "an event on a no-class day is flagged"

run "$N" syllabus Spring 2032 3703
assert_rc 0 "upper-division scaffold from the same calendar"
CALU="2032 - Spring/SP32 HIST 3703.md"
assert_has "$CALU" "## Week 10 (March 15-March 19): Spring Break" "upper: break week labelled in its heading"
assert_has "$CALU" "- Mon: No class (MLK Day)"                    "upper: single no-class day listed under its week"
assert_eq 17 "$(grep -c '^## Week' "$CALU")"                      "upper: week count from the calendar"
assert_has "$CALU" "- January 20: 100% refund"                    "upper: drops from the calendar"

run "$N" syllabus Spring 2032 1103 Online
CALO="2032 - Spring/SP32 HIST 1103 Online.md"
assert_has   "$CALO" "## Week 10 (March 15-March 21): Spring Break" "online: break week spans Mon-Sun"
assert_hasnt "$CALO" "MLK Day"                                       "online: single holidays are not listed"

run "$N" syllabus Spring 2032 3793 Flags --start 2032-01-13 --drop-full "Jan 99" --withdraw "Whenever"
FLAGS="2032 - Spring/SP32 HIST 3793 Flags.md"
assert_has "$FLAGS" "- Jan 99: 100% refund"            "flag overrides the calendar"
assert_has "$FLAGS" "- January 23: Partial refund"     "unflagged dates still come from the calendar"
assert_has "$FLAGS" "- Whenever: Withdraw deadline"    "every drop flag overrides"

cat > calendar/2032-summer.conf <<'CAL'
start  = 2032-06-07
finals = 2032-07-12
CAL
run "$N" syllabus Summer 2032 3703
assert_eq 6 "$(grep -c '^## Week' "2032 - Summer/SU32 HIST 3703.md")" "week count follows finals, not the 8-week default"
assert_has "2032 - Summer/SU32 HIST 3703.md" "[100% refund date]" "a calendar without deadlines leaves placeholders"
assert_hasnt "2032 - Summer/SU32 HIST 3703.md" "Six Week Grades" "summer with no six-week date omits the line"
assert_hasnt "2032 - Summer/SU32 HIST 3703.md" "six-week grades date]" "...rather than leaving a placeholder"
assert_has   "2032 - Summer/SU32 HIST 3703.md" "Withdraw deadline" "the other deadlines are kept"
run "$N" syllabus Summer 2032 3793 --sixweek "July 1"
assert_has "2032 - Summer/SU32 HIST 3793.md" "- July 1: Six Week Grades" "an explicit summer six-week date is kept"
run "$N" syllabus Summer 2032 1103 Online
assert_hasnt "2032 - Summer/SU32 HIST 1103 Online.md" "Six Week Grades" "online summer omits the line too"

run "$N" syllabus Fall 2034 3703
assert_rc 0 "no calendar for the term is not an error"
assert_in "no calendar/2034-fall.conf" "$OUT" "missing calendar is reported"
assert_in "no start date" "$OUT" "no start date: says why no breaks were placed"
assert_has "2034 - Fall/FA34 HIST 3703.md" "[100% refund date]" "no calendar -> placeholders"
assert_has "2034 - Fall/FA34 HIST 3703.md" "[six-week grades date]" "fall still keeps the placeholder when the date is missing"
assert_has "2034 - Fall/FA34 HIST 3703.md" "Student Hours: [student hours]" "student hours is a placeholder (upper)"
assert_has "$CAL" "Student Hours: [student hours]" "student hours is a placeholder (survey)"

section "new.sh — standard breaks (no calendar needed, only a start date)"
# 2033: MLK = Jan 17, Mar 17 is a Thursday, Labor Day = Sep 5, Thanksgiving = Nov 24
run "$N" syllabus Spring 2033 3703 --start 2033-01-10
assert_in "Verify against the registrar" "$OUT"  "a rule-placed Spring Break comes with a note to verify"
assert_in "Spring Break: Mar 14–18" "$OUT"       "the note lists Spring Break with its dates"
assert_hasnt <(echo "$OUT") "MLK"                "MLK Day (a fixed holiday) is not flagged for verification"
STD="2033 - Spring/SP33 HIST 3703.md"
assert_has "$STD" "- Mon: No class (MLK Day)"                         "Spring: MLK Day (third Monday of January)"
assert_has "$STD" "## Week 10 (March 14-March 18): Spring Break"      "Spring: break is the week of St. Patrick's Day"
run "$N" syllabus Fall 2033 3703 --start 2033-08-22
assert_hasnt <(echo "$OUT") "Verify against"        "Fall's breaks are fixed holidays: nothing to verify"
STD="2033 - Fall/FA33 HIST 3703.md"
assert_has "$STD" "- Mon: No class (Labor Day)"                       "Fall: Labor Day (first Monday of September)"
assert_has "$STD" "## Week 14 (November 21-November 25): Thanksgiving Break" "Fall: Thanksgiving week"
assert_hasnt "$STD" "MLK Day"                                          "Fall has no MLK Day"
run "$N" syllabus Summer 2033 3703 --start 2033-06-06
assert_hasnt <(echo "$OUT") "Verify against" "summer has no rule-based breaks, so no note"
assert_hasnt "2033 - Summer/SU33 HIST 3703.md" "No class"             "Summer has no standard breaks"
run "$N" syllabus Fall 2033 1493 --start 2033-08-22
assert_has "2033 - Fall/FA33 HIST 1493.md" "| 3 | Sep 5–9 | Mon:&nbsp;No class (Labor Day); " "survey table gets the standard break notes"
assert_has "2033 - Fall/FA33 HIST 1493.md" "| 14 | Nov 21–25 | No class | Thanksgiving Break |  |" "survey table gets the standard break row"

# Weekend St. Patrick's Day rolls FORWARD, as the registrar did in 2018 (Sat),
# 2019 (Sun) and 2024 (Sun); weekday years use the week containing it.
run "$N" syllabus Spring 2029 3703 --start 2029-01-08     # Mar 17 is a Saturday
assert_hasnt <(echo "$OUT") "St. Patrick" "no warning: the weekend case is not ambiguous"
assert_has "2029 - Spring/SP29 HIST 3703.md" "## Week 11 (March 19-March 23): Spring Break" "Saturday March 17 -> the following week"
run "$N" syllabus Spring 2030 3793 --start 2030-01-07     # Mar 17 is a Sunday
assert_has "2030 - Spring/SP30 HIST 3793.md" "## Week 11 (March 18-March 22): Spring Break" "Sunday March 17 -> the following week"
run "$N" syllabus Spring 2028 3703 --start 2028-01-10     # Mar 17 is a Friday
assert_has "2028 - Spring/SP28 HIST 3703.md" "## Week 10 (March 13-March 17): Spring Break" "Friday March 17 -> the week containing it"

# Calendar interplay
cat > calendar/2035-fall.conf <<'CAL'
start  = 2035-08-20
finals = 2035-12-10
no_class = 2035-09-03 | Fall Holiday
CAL
run "$N" syllabus Spring 2034 3703 --start 2034-01-09     # Mar 17 is a Friday
assert_in "Spring Break: Mar 13–17" "$OUT"          "Spring Break note appears for a term with no Spring calendar"
cat > calendar/2034-spring.conf <<'CAL'
start  = 2034-01-09
finals = 2034-05-01
no_class = 2034-03-13..2034-03-17 | Spring Break
CAL
run "$N" syllabus Spring 2034 3793
assert_hasnt <(echo "$OUT") "Verify against"        "a Spring Break named by the calendar is not flagged"
run "$N" syllabus Fall 2035 3703
OVR="2035 - Fall/FA35 HIST 3703.md"
assert_has   "$OVR" "- Mon: No class (Fall Holiday)" "a calendar entry keeps its own label on a standard-break day"
assert_hasnt "$OVR" "Labor Day"                      "...instead of the standard label"
assert_has   "$OVR" "Thanksgiving Break"             "other standard breaks still apply alongside calendar entries"

cat > calendar/2036-fall.conf <<'CAL'
start  = 2036-08-25
finals = 2036-12-15
standard_breaks = off
no_class = 2036-11-24..2036-11-28 | Registrar Break
CAL
run "$N" syllabus Fall 2036 3703
assert_hasnt <(echo "$OUT") "Verify against" "standard_breaks = off reports no rule-based breaks"
OFF="2036 - Fall/FA36 HIST 3703.md"
assert_hasnt "$OFF" "Labor Day"            "standard_breaks = off removes Labor Day"
assert_hasnt "$OFF" "Thanksgiving Break"   "standard_breaks = off removes Thanksgiving"
assert_has   "$OFF" "Registrar Break"      "the term's own breaks still apply"
printf 'standard_breaks = maybe\n' > calendar/2037-fall.conf
run "$N" syllabus Fall 2037 3703
assert_rc 1 "standard_breaks must be on or off"
assert_in "'on' or 'off'" "$OUT" "clean error for a bad standard_breaks value"
rm -f calendar/2037-fall.conf

section "new.sh — calendar errors (clean message, no orphan folder)"
bad_calendar() {   # $1 = description, $2 = file body, $3 = expected message
    printf '%s\n' "$2" > calendar/2040-fall.conf
    run "$N" syllabus Fall 2040 3703
    assert_rc 1 "$1: rejected"
    assert_in "$3" "$OUT" "$1: message"
    assert_hasnt <(echo "$OUT") "Traceback" "$1: no traceback"
    assert_absent "2040 - Fall" "$1: no orphan folder"
}
bad_calendar "unknown key"     "withdrawl = 2040-11-01"                   "unknown key 'withdrawl'"
bad_calendar "non-ISO date"    "start = 8/23/2040"                        "not a YYYY-MM-DD date"
bad_calendar "impossible date" "start = 2040-02-30"                       "not a valid calendar date"
bad_calendar "no_class label"  "no_class = 2040-09-03"                    "needs a label"
bad_calendar "reversed range"  "no_class = 2040-11-23..2040-11-20 | Bad" "ends before it starts"
bad_calendar "duplicate key"   $'start = 2040-08-20\nstart = 2040-08-21'  "start is set twice"
bad_calendar "finals < start"  $'start = 2040-08-20\nfinals = 2040-08-13' "before start"
printf 'start = 2040-08-20\nfinals = 2040-12-10\nwithdraw = 2039-11-01\n' > calendar/2040-fall.conf
run "$N" syllabus Fall 2040 3703
assert_in "outside the term" "$OUT" "a wrong-year deadline warns"
rm -f calendar/2040-fall.conf

section "new.sh calendar"
run "$N" calendar Fall 2041
assert_rc 0 "create a calendar stub"
assert_file "calendar/2041-fall.conf" "stub written to calendar/<year>-<season>.conf"
assert_has  "calendar/2041-fall.conf" "standard_breaks = off" "stub explains how to turn the standard breaks off"
assert_hasnt "calendar/2041-fall.conf" "2041-09" "stub contains no computed dates"
assert_has  "calendar/2041-fall.conf" "withdraw_wf" "stub has a W-or-F deadline field"
run python3 "$SB/schedule.py" values calendar/2041-fall.conf
assert_rc 0 "a blank stub is a valid calendar"
assert_eq "" "$OUT" "a blank stub supplies no dates (nothing is guessed)"
run "$N" calendar Fall 2041
assert_rc 1 "existing calendar is not overwritten"
run "$N" calendar Winter 2041
assert_rc 1 "calendar: unknown season rejected"
run "$N" calendar Fall
assert_rc 1 "calendar: missing year rejected"

section "committed calendars"
for f in "$REPO"/calendar/*.conf; do
    [ -e "$f" ] || continue
    run python3 "$SB/schedule.py" values "$f"
    assert_rc 0 "$(basename "$f") parses"
    assert_hasnt <(echo "$OUT") "warning" "$(basename "$f") raises no warnings"
done

section "survey schedule without a calendar"
run "$N" syllabus Spring 2036 1493
assert_rc 0 "survey without a calendar or --start scaffolds"
assert_has "2036 - Spring/SP36 HIST 1493.md" "| 1 |  | **Sun:&nbsp;Syllabus Quiz**" "week numbers with blank dates"
assert_has "2036 - Spring/SP36 HIST 1493.md" "(through [W or F deadline])" "no W-or-F date -> placeholder"
run "$N" syllabus Spring 2036 1103 --withdraw-wf "May 1"
assert_has "2036 - Spring/SP36 HIST 1103.md" "(through May 1) are the petition period" "--withdraw-wf overrides the calendar"

# ===========================================================================
section "build.sh — argument handling"
# ===========================================================================
run "$B" clean extra
assert_rc 2 "clean refuses extra arguments"
run "$B" bogus-arg
assert_rc 2 "unknown argument rejected"
run "$B" "does-not-exist.md"
assert_rc 2 "nonexistent .md rejected"

# ===========================================================================
if [ "$NO_BUILD" -eq 1 ]; then
    section "build.sh — smoke tests SKIPPED (--no-build)"
elif ! have_build_tools; then
    section "build.sh — smoke tests SKIPPED (toolchain not installed)"
else
    section "build.sh — build pipeline (uses tectonic; first run may fetch packages)"

    run "$B" "2027 - Fall/FA27 HIST 1493.md"
    assert_rc 0 "build a single syllabus"
    PDF="PDFs/2027 - Fall/FA27 HIST 1493.pdf"
    assert_file "$PDF" "PDF written to mirrored path under PDFs/"
    run qpdf --check "$PDF"
    assert_rc 0 "qpdf --check passes"
    assert_in "linearized" "$OUT" "PDF is linearized for web viewing"

    run "$B" "2027 - Fall/FA27 HIST 1493.md"
    assert_in "skip" "$OUT" "unchanged file is skipped on rebuild"

    run "$B" --force "2027 - Fall/FA27 HIST 1493.md"
    assert_in "built 1" "$OUT" "--force rebuilds ignoring timestamps"

    # A non-syllabus .md (no term prefix) is ignored by directory/all builds.
    printf '# handout\nnot a syllabus\n' > "2027 - Fall/Reading List.md"
    # A syllabus that breaks LaTeX, to prove per-file failure isolation.
    printf '%% Broken\n%% Fall 2027\n%% Dr. Eberle\n\n# X\n\n\\nosuchcmd\n' \
        > "2027 - Fall/FA27 HIST 2222 Broken.md"
    run "$B" --force "2027 - Fall"
    assert_rc 1 "a failing build makes build.sh exit non-zero"
    assert_in "failed 1" "$OUT" "the broken file is reported as failed"
    assert_file "PDFs/2027 - Fall/FA27 HIST 1493.pdf" "good files still build despite a sibling failure"
    assert_absent "PDFs/2027 - Fall/FA27 HIST 2222 Broken.pdf" "failed build leaves no partial PDF"
    assert_absent "PDFs/2027 - Fall/Reading List.pdf" "non-syllabus .md is ignored"

    # Path resolution relative to the current directory (not just repo root).
    ( cd "2027 - Fall" && "$B" "FA27 HIST 1493.md" >/dev/null 2>&1 )
    assert_eq 0 "$?" "build.sh accepts a path relative to the current directory"

    # gs/qpdf failure isolation: shadow the real binary with a fake one that
    # always fails, via a PATH-prepended directory, to prove build.sh reports
    # and isolates a failure in either post-processing stage, not just pandoc.
    FAKEBIN="$SB/fakebin"
    mkdir -p "$FAKEBIN"
    REALPATH="$PATH"

    cp "2027 - Fall/FA27 HIST 1493.md" "2027 - Fall/FA27 HIST 5555 GSFail.md"
    printf '#!/usr/bin/env bash\necho "fake gs: forced failure" >&2\nexit 1\n' > "$FAKEBIN/gs"
    chmod +x "$FAKEBIN/gs"
    export PATH="$FAKEBIN:$REALPATH"
    run "$B" "2027 - Fall/FA27 HIST 5555 GSFail.md"
    export PATH="$REALPATH"
    assert_rc 1 "gs failure fails the build"
    assert_in "gs failed" "$OUT" "gs failure reported"
    assert_in "(gs)" "$OUT" "gs failure attributed to the right tool"
    assert_absent "PDFs/2027 - Fall/FA27 HIST 5555 GSFail.pdf" "gs failure leaves no output PDF"
    rm -f "$FAKEBIN/gs"

    cp "2027 - Fall/FA27 HIST 1493.md" "2027 - Fall/FA27 HIST 6666 QPDFFail.md"
    printf '#!/usr/bin/env bash\necho "fake qpdf: forced failure" >&2\nexit 1\n' > "$FAKEBIN/qpdf"
    chmod +x "$FAKEBIN/qpdf"
    export PATH="$FAKEBIN:$REALPATH"
    run "$B" "2027 - Fall/FA27 HIST 6666 QPDFFail.md"
    export PATH="$REALPATH"
    assert_rc 1 "qpdf failure fails the build"
    assert_in "qpdf failed" "$OUT" "qpdf failure reported"
    assert_in "(qpdf)" "$OUT" "qpdf failure attributed to the right tool"
    assert_absent "PDFs/2027 - Fall/FA27 HIST 6666 QPDFFail.pdf" "qpdf failure leaves no output PDF"
    rm -f "$FAKEBIN/qpdf"

    run "$B" clean
    assert_rc 0 "clean removes the output directory"
    assert_absent "PDFs" "PDFs/ deleted by clean"
fi

# ===========================================================================
section "static analysis"
# ===========================================================================
if command -v shellcheck >/dev/null 2>&1; then
    run shellcheck -S style "$REPO/new.sh" "$REPO/build.sh" "$REPO/test.sh"
    assert_rc 0 "shellcheck (style) is clean"
else
    printf '  %s--   shellcheck not installed; skipped%s\n' "$DIM" "$RESET"
fi

# ---------------------------------------------------------------------------
printf '\n%s\n' "------------------------------------------------------------"
if [ "$FAIL" -eq 0 ]; then
    printf '%sall %d checks passed%s\n' "$GREEN" "$PASS" "$RESET"
    exit 0
else
    printf '%s%d passed, %d FAILED%s\n' "$RED" "$PASS" "$FAIL" "$RESET"
    exit 1
fi
