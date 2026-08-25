#!/usr/bin/env bash
# Assertions over the .qmd source and the rendered _site/. Run after `quarto render`.
set -uo pipefail
cd "$(dirname "$0")/.."

QMD=index.qmd
HTML=_site/index.html
fails=0

# want <label> <expected-count> <file> <grep-pattern>
want_n() {
  local label=$1 expect=$2 file=$3 pat=$4
  local got
  got=$(grep -oE "$pat" "$file" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$got" == "$expect" ]]; then
    printf '  ok   %-52s %s\n' "$label" "$got"
  else
    printf '  FAIL %-52s want %s, got %s\n' "$label" "$expect" "$got"; fails=$((fails+1))
  fi
}

# want <label> <file> <grep-pattern>   (at least one match)
want() {
  local label=$1 file=$2 pat=$3
  if grep -qE "$pat" "$file" 2>/dev/null; then
    printf '  ok   %s\n' "$label"
  else
    printf '  FAIL %s\n' "$label"; fails=$((fails+1))
  fi
}

# absent <label> <file> <grep-pattern>
absent() {
  local label=$1 file=$2 pat=$3
  if grep -qE "$pat" "$file" 2>/dev/null; then
    printf '  FAIL %-52s unexpected match\n' "$label"; fails=$((fails+1))
  else
    printf '  ok   %s\n' "$label"
  fi
}

[[ -f $HTML ]] || { echo "no $HTML -- run 'quarto render' first" >&2; exit 1; }

echo "== scaffolding =="
# Prove post/styles.css compiled INTO the theme bundle, not merely that a
# Quarto page exists. .progress-header only comes from our overlay.
if grep -qhE '\.progress-header' _site/index_files/libs/bootstrap/bootstrap*.min.css 2>/dev/null; then
  printf '  ok   %s\n' "styles.css compiled into theme bundle"
else
  printf '  FAIL %s\n' "styles.css NOT in theme bundle"; fails=$((fails+1))
fi
want "hero logo present"        "$HTML" 'class="header-logo"'
want "progress header present"  "$HTML" 'class="progress-header"'
want "reading progress track"   "$HTML" 'reading-progress-fill'
want "left ToC"                 "$HTML" 'quarto-sidebar-toc-left'
want "og:url absolute"          "$HTML" 'og:url"? content="https://openadmet\.github\.io/octant-cyp-inhib-blog-post/'
want "og:image absolute"        "$HTML" 'og:image"? content="https://openadmet\.github\.io/octant-cyp-inhib-blog-post/post/assets/title-image\.jpeg'
want "title image present"      "$HTML" 'class="title-image"'
want "title image alt text"     "$HTML" 'alt="Just a CYP might lower your inhibitions\.\.\."'
want "publication date"         "$HTML" 'August 24, 2026'
want "author block"             "$HTML" 'class="doc-authors"'
# Count well-formed ORCID iDs in the source and require the same number to reach
# the output. Self-adjusting as authors supply theirs, and prefix-agnostic: iDs
# issued recently start 0009-, not 0000-, so a 0000-anchored pattern undercounts.
orcid_src=$(grep -oE 'orcid\.org/[0-9]{4}-[0-9]{4}-[0-9]{4}-[0-9]{3}[0-9X]' "$QMD" | wc -l | tr -d ' ')
want_n "ORCID links (source has $orcid_src)" "$orcid_src" "$HTML" 'orcid\.org/[0-9]{4}-[0-9]{4}-[0-9]{4}-[0-9]{3}[0-9X]'
# Every author line carrying the ORCID shortcode must also carry a well-formed
# iD. Without this, a truncated or typo'd iD passes silently: the source count
# and the output count simply agree at the lower number.
orcid_shortcodes=$(grep -oE '\{\{< ai orcid' "$QMD" | wc -l | tr -d ' ')
want_n "ORCID iDs well-formed (shortcodes: $orcid_shortcodes)" "$orcid_shortcodes" "$QMD" 'orcid\.org/[0-9]{4}-[0-9]{4}-[0-9]{4}-[0-9]{3}[0-9X]'
absent "no DOI placeholder"     "$HTML" 'XXXXX|DOI-10\.5281'

echo
echo "== prose =="
want_n "h3 subsections"         3 "$HTML" '<h3[ >]'
want "Introduction heading"       "$HTML" 'id="introduction"'
want "Background heading"         "$HTML" 'id="background"'
want "Assay Design heading"       "$HTML" 'id="assay-design"'
want "Discussion heading"         "$HTML" 'id="discussion"'
want "Assay Effect Sizes heading" "$HTML" 'id="assay-effect-sizes"'
want "Tiering strategy heading"   "$HTML" 'id="tiering-strategy"'
want "Calling TDI heading"        "$HTML" 'id="calling-tdi"'
want "Conclusion heading"         "$HTML" 'id="conclusion"'
absent "no orphaned '3.' on Conclusion" "$HTML" '>3\. Conclusion<'
absent "no leftover escapes"      "$QMD"  '\\[<>\[\]~.()-]'
absent "no leftover image refs"   "$QMD"  '!\[\]\[image'
want "subscript notation rendered" "$HTML" 'pIC50<sub>TDI condition</sub>'

echo
echo "== static figures =="
want_n "webp img tags"        6 "$HTML" '<img src="post/figures/figure[1-6]\.webp"'
want_n "figure-toc headings"  7 "$HTML" '<h4 class="figure-toc'   # Task 6 bumps this to 7
want_n "figure-caption divs"  7 "$HTML" 'class="figure-caption"'   # Task 6 bumps this to 7
want_n "lightbox anchors"     6 "$HTML" 'class="[^"]*lightbox'
want_n "figure alt text"      6 "$HTML" '<img src="post/figures/figure[1-6]\.webp"[^>]*alt="[^"]+"'
want "Figure 1 caption lead"    "$HTML" '<strong>Figure 1:</strong>'
want "Figure 6 caption lead"    "$HTML" '<strong>Figure 6:</strong>'
absent "no italic captions left" "$QMD" '^\*Figure [0-9]'

echo
echo "== citations =="
want_n "cite-tip anchors"    5 "$HTML" 'class="cite-tip"'
want_n "cite-tip tooltips"   5 "$HTML" 'data-tooltip="[^"]+"'
want_n "reference list items" 5 "$HTML" 'id="ref-[1-5]"'
want "reference-list wrapper"  "$HTML" 'class="[^"]*reference-list'
want "References heading"      "$HTML" 'id="references"'
want "CYP1A2 not CYP1A23"      "$HTML" 'CYP2C9, and CYP1A2<'
# Citation 4 lives in Figure 1's caption as `kit<a ...>4</a>,` -- the anchor sits
# BEFORE the comma. Losing the anchor tags while keeping their text, the failure
# mode all five alternatives guard, therefore yields `kit4,`. `kit,?4` catches
# that and the `kit,4` variant too, and false-positives on neither.
absent "no glued citation digits" "$QMD" 'post1|GSTs2|CYP1A23|kit,?4|TDI5'

echo
echo "== interactive figure =="
want "iframe present"           "$HTML" '<iframe[^>]*figures/embed/index\.html'
want "iframe lazy"              "$HTML" '<iframe[^>]*loading="lazy"'
want "full-bleed wrapper"       "$HTML" 'figure-fullbleed'
want "open-in-tab escape link"  "$HTML" 'figure-escape'
want "autosize script"          "$HTML" 'fullbleedAutosize'
want "Figure 7 caption lead"    "$HTML" '<strong>Figure 7:</strong>'
absent "placeholder marker gone" "$QMD" 'insert interactive figure'

for f in index.html RDKit_minimal.wasm figure_detail_CYP1A2.json \
         figure_detail_CYP2C9.json figure_detail_CYP2D6.json figure_detail_CYP3A4.json; do
  if [[ -f "_site/figures/embed/$f" ]]; then printf '  ok   resource %s\n' "$f"
  else printf '  FAIL resource %s missing from _site\n' "$f"; fails=$((fails+1)); fi
done

echo
echo "== declared resources =="
# Every other declared/referenced asset must land in _site as well. Without
# this, dropping an entry from _quarto.yml's resources: would still render
# clean and pass every other assertion while the deployed page silently lost
# its logo or its social-card image.
for f in post/figures/figure1.webp post/figures/figure2.webp post/figures/figure3.webp \
         post/figures/figure4.webp post/figures/figure5.webp post/figures/figure6.webp \
         post/assets/openadmet-logo.png post/assets/title-image.jpeg; do
  if [[ -f "_site/$f" ]]; then printf '  ok   resource %s\n' "$f"
  else printf '  FAIL resource %s missing from _site\n' "$f"; fails=$((fails+1)); fi
done

echo
echo "== closing sections =="
want_n "h2 sections (all 8 now)" 8 "$HTML" '<h2 class="anchored"'
want "Acknowledgements heading" "$HTML" 'id="acknowledgements"'
want "Code and Data Availability" "$HTML" 'id="code-and-data-availability"'
want_n "doc-version rows"     2 "$HTML" 'class="doc-version"'
want "last-updated line"        "$HTML" 'Last updated: August 24, 2026'
want "github source link"       "$HTML" 'github\.com/OpenADMET/octant-cyp-inhib-blog-post'
# The post deliberately makes no claim about the parquet export's availability,
# in either direction: the release is planned but not announced, so the post
# stays silent and README.md carries the note for anyone rebuilding. Guard both
# ways -- a re-added "not yet available" invites the question, and any claim of
# availability would be false.
# The post commits to releasing the raw data after the challenge. That is a
# promise to readers, so assert it is present rather than merely permitted --
# it should not vanish in an edit. The post must still never claim the data is
# available now, nor link the reference repo's unrelated dataset.
want   "data-release commitment"  "$HTML" 'will be available on request following completion of the CYP inhibition challenge'
want   "names the samples, not raw" "$HTML" 'posterior samples of the inferred pIC50 and slope parameters'
# Every requestable dataset is gated on the challenge concluding. "available on
# request" ending a sentence would mean available now, which is what this guards.
absent "no ungated availability"  "$HTML" 'available on request\.|are available on request'
absent "no claim data is out now" "$HTML" 'dataset is available|available for download|available on HuggingFace'
absent "no fake dataset link"   "$HTML" 'huggingface\.co/datasets/openadmet/Octant_CYP_inhibition'

echo
if [[ $fails -eq 0 ]]; then echo "PASS -- all assertions held"; else echo "FAIL -- $fails assertion(s)"; exit 1; fi
