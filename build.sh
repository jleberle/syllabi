#!/usr/bin/env bash
#
# build.sh — render the markdown syllabi to web-optimized, OCR'd PDFs.
#
# For each *.md syllabus it:
#   1. runs pandoc with syllabus.tex to produce a PDF,
#   2. runs ocrmypdf to add a searchable text layer (only where missing),
#      compress, and linearize for fast web viewing,
#   3. writes the result under PDFs/, mirroring the source folder layout.
#
# Only files whose names start with a term prefix (FA/SP/SU + two digits) are
# treated as syllabi; other .md files in semester folders are ignored.
#
# Usage:
#   ./build.sh                      build every syllabus that changed since last run
#   ./build.sh -f|--force           rebuild everything, ignoring timestamps
#   ./build.sh clean                delete the PDFs/ output directory
#   ./build.sh "2026 - Spring"      build all syllabi in that semester folder
#   ./build.sh FILE.md ...          build only the named file(s)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$ROOT/syllabus.tex"
OUTDIR="$ROOT/PDFs"

FORCE=0
FILES=()
DIRS=()
for arg in "$@"; do
	case "$arg" in
		-f|--force) FORCE=1 ;;
		clean) rm -rf "$OUTDIR"; echo "removed $OUTDIR"; exit 0 ;;
		*.md) FILES+=("$arg") ;;
		*)
			if [ -d "$ROOT/$arg" ] || [ -d "$arg" ]; then
				DIRS+=("$arg")
			else
				echo "unknown argument: $arg" >&2; exit 2
			fi
			;;
	esac
done

for tool in pandoc ocrmypdf; do
	command -v "$tool" >/dev/null 2>&1 || { echo "error: $tool not found in PATH" >&2; exit 1; }
done

# Syllabus files start with a term prefix: FA/SP/SU followed by two digits.
is_syllabus() { [[ "$(basename "$1")" =~ ^(FA|SP|SU)[0-9]{2}[[:space:]] ]]; }

# Collect the source list: explicit files, named directories, or all syllabi.
if [ "${#DIRS[@]}" -gt 0 ]; then
	for dir in "${DIRS[@]}"; do
		case "$dir" in /*) absdir="$dir" ;; *) absdir="$ROOT/$dir" ;; esac
		while IFS= read -r -d '' md; do
			is_syllabus "$md" && FILES+=("$md")
		done < <(find "$absdir" -maxdepth 1 -name '*.md' -print0 | sort -z)
	done
elif [ "${#FILES[@]}" -eq 0 ]; then
	while IFS= read -r -d '' md; do
		is_syllabus "$md" && FILES+=("$md")
	done < <(find "$ROOT" -name '*.md' -not -path "$OUTDIR/*" -not -path "$ROOT/.git/*" -print0 | sort -z)
fi

JOBS=$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 4)
RESDIR="$(mktemp -d)"
trap 'rm -rf "$RESDIR"' EXIT

# Build one file in a subshell; writes "built" or "failed:<rel> (<tool>)" to $4.
_build_one() {
	local abs="$1" rel="$2" out="$3" resfile="$4"
	local tmpdir tmp log

	printf 'build  %s\n' "$rel"
	mkdir -p "$(dirname "$out")"
	tmpdir="$(mktemp -d)"
	tmp="$tmpdir/syllabus.pdf"
	log="$tmpdir/build.log"

	# pandoc runs from ROOT so the template's relative logo path resolves.
	if ! (cd "$ROOT" && pandoc "$abs" --template="$TEMPLATE" -o "$tmp") 2>"$log"; then
		{ printf '  ! pandoc failed:\n'; sed 's/^/    /' "$log"; } >&2
		rm -rf "$tmpdir"; echo "failed:$rel (pandoc)" > "$resfile"; return
	fi

	if ! ocrmypdf \
		--skip-text \
		--optimize 2 \
		--fast-web-view 1 \
		--output-type pdf \
		--quiet \
		"$tmp" "$out" 2>"$log"; then
		{ printf '  ! ocrmypdf failed:\n'; sed 's/^/    /' "$log"; } >&2
		rm -rf "$tmpdir"; echo "failed:$rel (ocrmypdf)" > "$resfile"; return
	fi

	rm -rf "$tmpdir"
	echo "built" > "$resfile"
}

skipped=0
jobidx=0
declare -a pids=()

for md in "${FILES[@]}"; do
	# Normalize to an absolute path so the relative layout under PDFs/ is stable.
	case "$md" in /*) abs="$md" ;; *) abs="$ROOT/${md#./}" ;; esac
	rel="${abs#"$ROOT"/}"
	out="$OUTDIR/${rel%.md}.pdf"

	if [ "$FORCE" -eq 0 ] && [ -f "$out" ] && [ "$out" -nt "$abs" ]; then
		printf 'skip   %s\n' "$rel"
		skipped=$((skipped + 1))
		continue
	fi

	resfile="$RESDIR/$jobidx"
	jobidx=$((jobidx + 1))
	_build_one "$abs" "$rel" "$out" "$resfile" &
	pids+=($!)

	# When at the concurrency limit, wait for the oldest job before launching more.
	if [ "${#pids[@]}" -ge "$JOBS" ]; then
		wait "${pids[0]}" || true
		pids=("${pids[@]:1}")  # drop the completed slot
	fi
done

# Wait for remaining in-flight jobs.
for pid in "${pids[@]+"${pids[@]}"}"; do
	wait "$pid" || true
done

# Collect results written by each subshell.
built=0 failed=0
declare -a FAILS=()
for resfile in "$RESDIR"/*; do  # glob expands to literal string if no files match
	[ -f "$resfile" ] || continue
	result="$(< "$resfile")"
	case "$result" in
		built)    built=$((built + 1)) ;;
		failed:*) failed=$((failed + 1)); FAILS+=("${result#failed:}") ;;
	esac
done

echo "---"
printf 'built %d, skipped %d, failed %d\n' "$built" "$skipped" "$failed"
if [ "$failed" -gt 0 ]; then
	printf '  %s\n' "${FAILS[@]}" >&2
	exit 1
fi
