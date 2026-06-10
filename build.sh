#!/usr/bin/env bash
#
# build.sh — render the markdown syllabi to compressed, linearized PDFs.
#
# For each *.md syllabus it:
#   1. runs pandoc with syllabus.tex to produce a PDF,
#   2. runs ghostscript to compress (screen-quality images, lossless text),
#   3. runs qpdf to linearize for fast web viewing,
#   4. writes the result under PDFs/, mirroring the source folder layout.
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

# The job pool uses `wait -n`, which needs bash >= 4.3 (macOS system bash is 3.2).
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
	echo "error: bash >= 4.3 required, found $BASH_VERSION (on macOS: brew install bash)" >&2
	exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$ROOT/syllabus.tex"
LOGO="$ROOT/osulogo.pdf"
OUTDIR="$ROOT/PDFs"

# `clean` is only honored as the sole argument so a stray word in a longer
# command line can't wipe the output directory.
if [ "${1:-}" = "clean" ]; then
	[ $# -eq 1 ] || { echo "usage: ./build.sh clean (no other arguments)" >&2; exit 2; }
	rm -rf "$OUTDIR"; echo "removed $OUTDIR"; exit 0
fi

FORCE=0
FILES=()
DIRS=()
for arg in "$@"; do
	case "$arg" in
		-f|--force) FORCE=1 ;;
		*.md)
			# Resolve the same way the build loop does, so a typo'd name
			# fails here instead of as a confusing pandoc error.
			case "$arg" in /*) f="$arg" ;; *) f="$ROOT/${arg#./}" ;; esac
			[ -f "$f" ] || { echo "no such file: $arg" >&2; exit 2; }
			FILES+=("$arg")
			;;
		*)
			if [ -d "$ROOT/$arg" ] || [ -d "$arg" ]; then
				DIRS+=("$arg")
			else
				echo "unknown argument: $arg" >&2; exit 2
			fi
			;;
	esac
done

for tool in pandoc gs qpdf; do
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
	tmpdir="$(mktemp -d)"
	tmp="$tmpdir/syllabus.pdf"
	log="$tmpdir/build.log"

	# pandoc runs from ROOT so the template's relative logo path resolves.
	if ! (cd "$ROOT" && pandoc "$abs" --template="$TEMPLATE" -o "$tmp") 2>"$log"; then
		{ printf '  ! pandoc failed:\n'; sed 's/^/    /' "$log"; } >&2
		rm -rf "$tmpdir"; echo "failed:$rel (pandoc)" > "$resfile"; return
	fi

	local compressed="$tmpdir/compressed.pdf"

	# /ebook: 150dpi images, lossless text/vectors — sharp logo, small file.
	if ! gs -q -dBATCH -dNOPAUSE -dSAFER \
		-sDEVICE=pdfwrite \
		-dCompatibilityLevel=1.7 \
		-dPDFSETTINGS=/ebook \
		-dEmbedAllFonts=true \
		-dSubsetFonts=true \
		-dCompressFonts=true \
		-sOutputFile="$compressed" \
		"$tmp" 2>"$log"; then
		{ printf '  ! gs failed:\n'; sed 's/^/    /' "$log"; } >&2
		rm -rf "$tmpdir"; echo "failed:$rel (gs)" > "$resfile"; return
	fi

	# Create the output directory only now, so a failed build doesn't leave
	# an empty folder behind.
	mkdir -p "$(dirname "$out")"
	if ! qpdf --linearize "$compressed" "$out" 2>"$log"; then
		{ printf '  ! qpdf failed:\n'; sed 's/^/    /' "$log"; } >&2
		rm -rf "$tmpdir"; echo "failed:$rel (qpdf)" > "$resfile"; return
	fi

	rm -rf "$tmpdir"
	echo "built" > "$resfile"
}

skipped=0
jobidx=0
running=0

for md in "${FILES[@]}"; do
	# Normalize to an absolute path so the relative layout under PDFs/ is stable.
	case "$md" in /*) abs="$md" ;; *) abs="$ROOT/${md#./}" ;; esac
	rel="${abs#"$ROOT"/}"
	out="$OUTDIR/${rel%.md}.pdf"

	# Rebuild if the source, the shared template, or the logo is newer than
	# the output — editing branding/layout should invalidate every PDF.
	if [ "$FORCE" -eq 0 ] && [ -f "$out" ] \
		&& [ "$out" -nt "$abs" ] \
		&& [ "$out" -nt "$TEMPLATE" ] \
		&& [ "$out" -nt "$LOGO" ]; then
		printf 'skip   %s\n' "$rel"
		skipped=$((skipped + 1))
		continue
	fi

	resfile="$RESDIR/$jobidx"
	jobidx=$((jobidx + 1))
	_build_one "$abs" "$rel" "$out" "$resfile" &
	running=$((running + 1))

	# At the concurrency limit, reap whichever job finishes first (not the
	# oldest) so a single slow file doesn't stall otherwise-free slots.
	if [ "$running" -ge "$JOBS" ]; then
		wait -n || true
		running=$((running - 1))
	fi
done

# Wait for remaining in-flight jobs.
wait

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
