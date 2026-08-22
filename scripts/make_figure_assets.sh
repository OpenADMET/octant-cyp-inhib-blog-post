#!/usr/bin/env bash
# Regenerate post/figures/*.webp from the PNG exports in scratch/.
#
# scratch/ is gitignored, so the webp outputs are committed: they are derived
# from inputs that are not versioned. Re-run this only when the source PNGs
# change, then commit the result.
#
# 2400px on the long edge keeps a lightbox zoom sharp at the ~1600px lightbox
# width without carrying the full 7350px export. figure4.png's source export is
# the smallest of the six and is NOT upscaled if it is already under the cap --
# it may look softer than the other five.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:-scratch}"
OUT="post/figures"
MAXEDGE=2400
QUALITY=90

mkdir -p "$OUT"
# BSD/macOS mktemp only randomizes a trailing XXXXXX -- a template with a
# literal suffix after it (e.g. "....XXXXXX.png") is taken as-is, giving every
# invocation the same predictable path. Keep XXXXXX trailing and use the
# `png:` format prefix on the magick output target instead of a .png suffix.
tmp="$(mktemp "${TMPDIR:-/tmp}/make_figure_assets.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

for n in 1 2 3 4 5 6; do
  in="$SRC/figure$n.png"
  [[ -f "$in" ]] || { echo "missing $in -- stage the PNG exports in $SRC/" >&2; exit 1; }
  # Piping `magick ... png:- | cwebp -- - -o ...` silently drops the -o target
  # on this ImageMagick/cwebp build, so resize to a temp PNG first.
  magick "$in" -resize "${MAXEDGE}x${MAXEDGE}>" -strip "png:$tmp"
  cwebp -quiet -q "$QUALITY" "$tmp" -o "$OUT/figure$n.webp"
  printf '%-24s %8s -> %-24s %8s\n' \
    "$(basename "$in")" "$(du -h "$in" | cut -f1)" \
    "$(basename "$OUT/figure$n.webp")" "$(du -h "$OUT/figure$n.webp" | cut -f1)"
done
