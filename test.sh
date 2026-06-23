#!/usr/bin/env bash
#
# test.sh — regression tests for new.sh and build.sh.
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
cp "$REPO/new.sh" "$REPO/build.sh" "$REPO/syllabus.tex" "$REPO/osulogo.pdf" "$SB"/
cp -R "$REPO/templates" "$SB/templates"
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

run "$N" syllabus Fall 2027
assert_rc 1 "too few positional args rejected"

run "$N" syllabus Fall 2027 1493 --start
assert_rc 1 "missing --start value rejected"

# ===========================================================================
section "new.sh — schedule generation (2030-08-26 is a Monday)"
# ===========================================================================
run "$N" syllabus Fall 2030 1103 --start 2030-08-26
SCHED_IP="2030 - Fall/FA30 HIST 1103.md"
assert_has "$SCHED_IP" "## Week 1 (August 26-August 30)" "in-person week spans Mon-Fri"
assert_eq 16 "$(grep -c '^## Week' "$SCHED_IP")" "Fall = 16 weeks"

run "$N" syllabus Fall 2030 1103 Online --start 2030-08-26
SCHED_ON="2030 - Fall/FA30 HIST 1103 Online.md"
assert_has "$SCHED_ON" "## Week 1 (August 26-September 1)" "online week spans Mon-Sun"
assert_has "$SCHED_ON" "A Note About Online Delivery" "online skeleton selected for online descriptor"
assert_hasnt "$IP"     "A Note About Online Delivery" "in-person skeleton omits the online note"

run "$N" syllabus Summer 2030 1103 Online --start 2030-06-02
assert_eq 8 "$(grep -c '^## Week' "2030 - Summer/SU30 HIST 1103 Online.md")" "Summer = 8 weeks"

run "$N" syllabus Fall 2030 2023 --start 2030-08-28   # Wednesday start
assert_has "2030 - Fall/FA30 HIST 2023.md" "## Week 1 (August 26-August 30)" "mid-week start snaps back to Monday"

run "$N" syllabus Spring 2030 1493
assert_rc 0 "syllabus without --start scaffolds"
NODATE="2030 - Spring/SP30 HIST 1493.md"
assert_has   "$NODATE" "## Week 1"  "no --start -> bare week heading"
assert_hasnt "$NODATE" "## Week 1 (" "no --start -> no date range"
assert_eq 16 "$(grep -c '^## Week' "$NODATE")" "no --start still produces 16 Fall weeks"

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
