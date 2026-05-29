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
# Usage:
#   ./build.sh                 build every syllabus that changed since last run
#   ./build.sh -f|--force      rebuild everything, ignoring timestamps
#   ./build.sh clean           delete the PDFs/ output directory
#   ./build.sh FILE.md ...     build only the named file(s)
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$ROOT/syllabus.tex"
OUTDIR="$ROOT/PDFs"

FORCE=0
FILES=()
for arg in "$@"; do
	case "$arg" in
		-f|--force) FORCE=1 ;;
		clean) rm -rf "$OUTDIR"; echo "removed $OUTDIR"; exit 0 ;;
		*.md) FILES+=("$arg") ;;
		*) echo "unknown argument: $arg" >&2; exit 2 ;;
	esac
done

for tool in pandoc ocrmypdf; do
	command -v "$tool" >/dev/null 2>&1 || { echo "error: $tool not found in PATH" >&2; exit 1; }
done

# Collect the source list: explicit files, or every *.md outside PDFs/ and .git.
if [ "${#FILES[@]}" -eq 0 ]; then
	while IFS= read -r -d '' md; do
		FILES+=("$md")
	done < <(find "$ROOT" -name '*.md' -not -path "$OUTDIR/*" -not -path "$ROOT/.git/*" -print0 | sort -z)
fi

built=0 skipped=0 failed=0
declare -a FAILS=()

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

	printf 'build  %s\n' "$rel"
	mkdir -p "$(dirname "$out")"
	tmpdir="$(mktemp -d)"
	tmp="$tmpdir/syllabus.pdf"

	# pandoc runs from ROOT so the template's relative logo path resolves.
	if ! (cd "$ROOT" && pandoc "$abs" --template="$TEMPLATE" -o "$tmp") 2>/tmp/syllabi-build.log; then
		echo "  ! pandoc failed:" >&2; sed 's/^/    /' /tmp/syllabi-build.log >&2
		rm -rf "$tmpdir"; failed=$((failed + 1)); FAILS+=("$rel (pandoc)"); continue
	fi

	if ! ocrmypdf \
		--skip-text \
		--optimize 2 \
		--fast-web-view 0 \
		--output-type pdf \
		--quiet \
		"$tmp" "$out" 2>/tmp/syllabi-build.log; then
		echo "  ! ocrmypdf failed:" >&2; sed 's/^/    /' /tmp/syllabi-build.log >&2
		rm -rf "$tmpdir"; failed=$((failed + 1)); FAILS+=("$rel (ocrmypdf)"); continue
	fi

	rm -rf "$tmpdir"
	built=$((built + 1))
done

echo "---"
printf 'built %d, skipped %d, failed %d\n' "$built" "$skipped" "$failed"
if [ "$failed" -gt 0 ]; then
	printf '  %s\n' "${FAILS[@]}" >&2
	exit 1
fi
