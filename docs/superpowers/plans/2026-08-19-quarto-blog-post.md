# Quarto Blog Post Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn this figure-only repo into a Quarto-rendered HTML blog post that embeds the existing interactive TDI-shift figure, styled to match `OpenADMET/Octant_CYP_blog_post`, published to GitHub Pages.

**Architecture:** One hand-written `.qmd` at the repo root, rendered by Quarto to `_site/index.html`. The post's prose comes from a Google Docs markdown export in gitignored `scratch/`; figures 1-6 come from PNGs in the same place, converted to committed webp. The prebuilt interactive figure in `figures/embed/` is served as a Quarto resource and embedded in a same-origin, auto-height iframe. No code executes at render time, so CI needs Quarto only.

**Tech Stack:** Quarto 1.10.18 (local) with the `lux` bootswatch theme + a `post/styles.css` overlay; the `schochastics/academicons` Quarto extension for ORCID icons; `cwebp`/`magick` for image conversion; GitHub Actions + `peaceiris/actions-gh-pages` for deploy.

**Spec:** `docs/superpowers/specs/2026-08-19-quarto-blog-post-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

- **Branch:** `convert-to-quarto`. Do not create new branches. Do not commit to `main`.
- **Do not modify the figure pipeline.** `src/`, `R/`, `scripts/build_figure_data.R`, `scripts/verify_data.sh`, `tests/`, `build.py`, `data/` are off-limits. Verified at the end by `git diff --stat bdf24c3 -- src/ R/ tests/ build.py data/ scripts/build_figure_data.R scripts/verify_data.sh` being empty.
- **No Python dependencies.** `build.py` is stdlib-only. Do not add `pyproject.toml` or `uv.lock`.
- **Do not run the R test suite or `renv::snapshot()` on the dev machine.** `duckdb` and `posterior` are absent locally (`helper-source.R:4` aborts at `library(duckdb)`), and `scratch/data/` is not staged. Runnability is validated later on the author's server.
- **Publication date:** `August 24, 2026`.
- **Site URL:** `https://openadmet.github.io/octant-cyp-inhib-blog-post/`.
- **No DOI.** The source says `DOI: XXXXX`; ship no DOI badge and no placeholder.
- **Authors:** Lauren Orr, Scott Simpkins, Hugo MacDermott-Opeskin, Naomi Handly, Pat Walters. Known ORCIDs: Simpkins `0000-0002-5997-2838`, MacDermott-Opeskin `0000-0002-7393-7457`. The other three render as plain names, structured so each ORCID drops in as a one-line edit.
- **Reference repo path:** `/Users/scott/Octant/software/Octant_CYP_blog_post` — read-only source for `post/styles.css`, `post/assets/openadmet-logo.png`, and `_extensions/`.
- **`scratch/` is gitignored.** Anything derived from it (the webp figures) must be committed, because its inputs are not versioned.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `scripts/make_figure_assets.sh` | Regenerate `post/figures/*.webp` from `scratch/*.png`. Documents provenance of committed derived files. | 1 |
| `post/figures/figure1..6.webp` | The six static figures, committed. | 1 |
| `post/assets/openadmet-logo.png` | Header + hero logo. | 1 |
| `post/assets/og-preview.png` | Social link-preview image. | 1 |
| `_extensions/schochastics/academicons/` | ORCID icon shortcode. | 1 |
| `scripts/check_post.sh` | The test harness. Asserts against both the `.qmd` source and the rendered `_site/`. Grows one section per task. | 2-8 |
| `_quarto.yml` | Project + HTML format config, resources, before/after-body injections. | 2 |
| `post/styles.css` | All styling. Reference repo's file minus ggiraph, plus iframe and reference-list rules. | 2, 5, 6 |
| `cyp-inhib-blog-post.qmd` | The post. Front matter and authors (2), prose and figures (3, 4), iframe (6), closing sections (7). | 2-7 |
| `.gitignore` | Add Quarto build artifacts. | 2 |
| `.quartoignore` | Keep Quarto out of `scratch/` and `.git`. | 2 |
| `.github/workflows/render-deploy.yml` | Render + publish to `gh-pages`. | 8 |
| `LICENSE` | Apache 2.0, copied from the reference repo. Linked by the Task 7 footer. | 8 |
| `README.md` | Corrected data-staging prose; render/deploy instructions. | 8 |
| `CLAUDE.md` | Repo orientation, modeled on the reference repo's. | 8 |
| `renv.lock`, `.Rprofile`, `renv/` | R dependency lock for the figure pipeline. **Blocked on author input.** | 9 |

---

### Task 1: Asset pipeline

**Files:**
- Create: `scripts/make_figure_assets.sh`
- Create: `post/figures/figure1.webp` .. `figure6.webp`
- Create: `post/assets/openadmet-logo.png`, `post/assets/og-preview.png`
- Create: `_extensions/schochastics/academicons/` (copied tree)

**Interfaces:**
- Consumes: `scratch/figure1..6.png` (gitignored inputs, present on the dev machine).
- Produces: `post/figures/figureN.webp` for N in 1..6; `post/assets/openadmet-logo.png`; `post/assets/og-preview.png`; the `{{< ai orcid >}}` shortcode.

- [ ] **Step 1: Write the conversion script**

`scripts/make_figure_assets.sh`:

```bash
#!/usr/bin/env bash
# Regenerate post/figures/*.webp from the PNG exports in scratch/.
#
# scratch/ is gitignored, so the webp outputs are committed: they are derived
# from inputs that are not versioned. Re-run this only when the source PNGs
# change, then commit the result.
#
# 2400px on the long edge keeps a lightbox zoom sharp at the ~1600px lightbox
# width without carrying the full 7350px export. figure4.png is 928x646 and is
# NOT upscaled -- it will look softer than the other five.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:-scratch}"
OUT="post/figures"
MAXEDGE=2400
QUALITY=90

mkdir -p "$OUT"
for n in 1 2 3 4 5 6; do
  in="$SRC/figure$n.png"
  [[ -f "$in" ]] || { echo "missing $in -- stage the PNG exports in $SRC/" >&2; exit 1; }
  magick "$in" -resize "${MAXEDGE}x${MAXEDGE}>" -strip png:- \
    | cwebp -quiet -q "$QUALITY" -- - -o "$OUT/figure$n.webp"
  printf '%-24s %8s -> %-24s %8s\n' \
    "$(basename "$in")" "$(du -h "$in" | cut -f1)" \
    "$(basename "$OUT/figure$n.webp")" "$(du -h "$OUT/figure$n.webp" | cut -f1)"
done
```

`-resize "2400x2400>"` only shrinks (the `>` flag), so figure4 passes through untouched.

- [ ] **Step 2: Run it and verify it fails cleanly on a missing input**

```bash
chmod +x scripts/make_figure_assets.sh
./scripts/make_figure_assets.sh /nonexistent
```
Expected: `missing /nonexistent/figure1.png -- stage the PNG exports in /nonexistent/`, exit 1.

- [ ] **Step 3: Run it for real**

```bash
./scripts/make_figure_assets.sh
```
Expected: six lines of `figureN.png <size> -> figureN.webp <size>`, every output smaller than its input.

- [ ] **Step 4: Verify dimensions and aspect ratios survived**

```bash
python3 - <<'PY'
import pathlib, re, subprocess
EXPECT = {1:(7350,4110), 2:(6600,4800), 3:(3600,3000), 4:(1712,1166), 5:(3000,2580), 6:(2700,3900)}
for n,(sw,sh) in EXPECT.items():
    p = pathlib.Path(f"post/figures/figure{n}.webp")
    out = subprocess.run(["magick","identify","-format","%w %h",str(p)],
                         capture_output=True, text=True).stdout.split()
    w, h = int(out[0]), int(out[1])
    ar_src, ar_out = sw/sh, w/h
    long_edge = max(w,h)
    ok = abs(ar_src-ar_out)/ar_src < 0.01 and long_edge <= 2400
    print(f"figure{n}.webp {w}x{h:<5} long={long_edge:<5} ar {ar_src:.3f}->{ar_out:.3f} "
          f"{'OK' if ok else 'FAIL'}")
    assert ok, f"figure{n} failed"
print("all six OK")
PY
```
Expected: `all six OK`. figure4 stays 928x646.

- [ ] **Step 5: Copy the logo and the academicons extension from the reference repo**

```bash
REF=/Users/scott/Octant/software/Octant_CYP_blog_post
mkdir -p post/assets _extensions
cp "$REF/post/assets/openadmet-logo.png" post/assets/
cp -R "$REF/_extensions/schochastics" _extensions/
ls -la post/assets/ && find _extensions -type f | sort
```
Expected: the logo plus 8 academicons files (`_extension.yml`, `academicons.lua`, 2 CSS, 4 webfonts).

- [ ] **Step 6: Build the og-preview image**

Social cards are 1200x630 (ratio 1.905). Figure 1 (the assay workflow) is 7350x4110 — ratio **1.788**, very nearly the card's — so it fills the frame with only thin side bars. Do **not** use figure 6: at 2700x3900 it is portrait (ratio 0.69) and would letterbox to a ~436px-wide sliver between two white bars.

```bash
magick post/figures/figure1.webp \
  -resize '1200x630' -background white -gravity center -extent 1200x630 \
  -strip post/assets/og-preview.png
magick identify -format '%wx%h %b\n' post/assets/og-preview.png
```
Expected: `1200x630` and a size well under 1 MB.

- [ ] **Step 7: Commit**

```bash
git add scripts/make_figure_assets.sh post/figures post/assets _extensions
git commit -m "Add static figure, logo and ORCID-icon assets for the post

Convert the six PNG exports to webp at <=2400px on the long edge. scratch/ is
gitignored, so these derived files are committed and make_figure_assets.sh
records how to regenerate them. figure4 is 928x646 at source and is not
upscaled."
```

---

### Task 2: Quarto scaffolding that renders an empty post

**Files:**
- Create: `_quarto.yml`, `.quartoignore`, `post/styles.css`, `cyp-inhib-blog-post.qmd`, `scripts/check_post.sh`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: Task 1's `post/assets/openadmet-logo.png`, `post/assets/og-preview.png`, `_extensions/schochastics/academicons/`.
- Produces: `_site/index.html`; the `.doc-authors`, `.figure-caption`, `.figure-toc`, `.cite-tip`, `.reference-list`, `.doc-version` CSS classes used by Tasks 3-7; `scripts/check_post.sh` with a `want`/`want_n` assertion API that later tasks extend.

- [ ] **Step 1: Write the failing test harness**

`scripts/check_post.sh`:

```bash
#!/usr/bin/env bash
# Assertions over the .qmd source and the rendered _site/. Run after `quarto render`.
set -uo pipefail
cd "$(dirname "$0")/.."

QMD=cyp-inhib-blog-post.qmd
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
if grep -qhE '\.progress-header' _site/cyp-inhib-blog-post_files/libs/bootstrap/bootstrap*.min.css 2>/dev/null; then
  printf '  ok   %s\n' "styles.css compiled into theme bundle"
else
  printf '  FAIL %s\n' "styles.css NOT in theme bundle"; fails=$((fails+1))
fi
want "hero logo present"        "$HTML" 'class="header-logo"'
want "progress header present"  "$HTML" 'class="progress-header"'
want "reading progress track"   "$HTML" 'reading-progress-fill'
want "left ToC"                 "$HTML" 'quarto-sidebar-toc-left'
want "og:url absolute"          "$HTML" 'og:url"? content="https://openadmet\.github\.io/octant-cyp-inhib-blog-post/'
want "og:image absolute"        "$HTML" 'og:image"? content="https://openadmet\.github\.io/octant-cyp-inhib-blog-post/post/assets/og-preview\.png'
want "publication date"         "$HTML" 'August 24, 2026'
want "author block"             "$HTML" 'class="doc-authors"'
want_n "ORCID icons (2 known)" 2 "$HTML" 'orcid\.org/0000-000'
absent "no DOI placeholder"     "$HTML" 'XXXXX|DOI-10\.5281'

echo
if [[ $fails -eq 0 ]]; then echo "PASS -- all assertions held"; else echo "FAIL -- $fails assertion(s)"; exit 1; fi
```

- [ ] **Step 2: Run it to verify it fails**

```bash
chmod +x scripts/check_post.sh && ./scripts/check_post.sh
```
Expected: `no _site/index.html -- run 'quarto render' first`, exit 1.

- [ ] **Step 3: Write `_quarto.yml`**

```yaml
project:
  output-dir: _site
  render:
    - cyp-inhib-blog-post.qmd
  resources:
    - post/assets/openadmet-logo.png
    - post/assets/og-preview.png
    - figures/embed/**

format:
  html:
    open-graph:
      image: post/assets/og-preview.png
    twitter-card:
      image: post/assets/og-preview.png
      card-style: summary_large_image
    theme:
      - lux
      - post/styles.css
    grid:
      body-width: 850px
    toc: true
    toc-location: left
    toc-expand: 2
    toc-depth: 4
    smooth-scroll: true
    number-sections: false
    lightbox: true
    include-before-body:
      - text: |
          <div class="progress-header">
            <a href="https://openadmet.ghost.io/"><img src="post/assets/openadmet-logo.png" alt="OpenADMET" class="progress-header-logo"></a>
            <span class="progress-header-title">Lowering Inhibitions, One CYP at a Time</span>
            <div class="reading-progress-track"><div class="reading-progress-fill"></div></div>
          </div>
          <a href="https://openadmet.ghost.io/"><img src="post/assets/openadmet-logo.png" alt="OpenADMET logo" class="header-logo"></a>
    include-after-body:
      - text: |
          <script>
            // Enable ToC figure entries after first scroll (keeps ToC clean on load)
            window.addEventListener('scroll', function() {
              document.body.classList.add('toc-scrolled');
            }, { once: true });

            // Progress header: show after scrolling past hero, update progress bar
            (function() {
              var header = document.querySelector('.progress-header');
              var fill = document.querySelector('.reading-progress-fill');
              var tocSidebar = document.getElementById('quarto-sidebar-toc-left');
              if (!header || !fill) return;
              var threshold = 300; // px before header appears
              window.addEventListener('scroll', function() {
                var scrollTop = window.scrollY;
                var docHeight = document.documentElement.scrollHeight - window.innerHeight;
                var pct = docHeight > 0 ? Math.min(scrollTop / docHeight * 100, 100) : 0;
                fill.style.width = pct + '%';
                var past = scrollTop > threshold;
                header.classList.toggle('visible', past);
                if (tocSidebar) tocSidebar.classList.toggle('toc-visible', past);
              });
            })();

            // Copy figure captions into lightbox descriptions
            document.querySelectorAll('.figure-caption').forEach(function(cap) {
              var prev = cap.previousElementSibling;
              if (!prev) return;
              var link = prev.querySelector('a.lightbox');
              if (!link) return;
              link.setAttribute('data-description', cap.innerHTML);
            });
          </script>
```

Differences from the reference repo, all deliberate: no `execute:`/`knitr:` blocks (no code cells), no ggiraph fullscreen-modal JS (no ggiraph widgets), no banner video resource, and `figures/embed/**` added.

- [ ] **Step 4: Write `.quartoignore` and extend `.gitignore`**

`.quartoignore`:
```
.git
scratch
```

Append to `.gitignore`:
```
# Quarto
/.quarto/
_freeze/
_site/
**/*.quarto_ipynb
cyp-inhib-blog-post_files/
*.rmarkdown
```

`_site/` is **not** tracked: CI regenerates it from committed inputs on every push. (The reference repo does not track its `_site/` either, despite its own CLAUDE.md saying so three times — verified: that repo gitignores `_site/` and has zero commits touching it.)

- [ ] **Step 5: Create `post/styles.css` from the reference repo**

```bash
REF=/Users/scott/Octant/software/Octant_CYP_blog_post
python3 - <<'PY'
import pathlib
ref = pathlib.Path("/Users/scott/Octant/software/Octant_CYP_blog_post/post/styles.css")
lines = ref.read_text().splitlines(keepends=True)
# Drop section 7 (ggiraph fullscreen) -- no ggiraph widgets in this post.
start = next(i for i,l in enumerate(lines) if "7. ggiraph fullscreen" in l) - 2
end   = next(i for i,l in enumerate(lines) if "8. Citation tooltips" in l) - 2
out = lines[:start] + lines[end:]
pathlib.Path("post/styles.css").write_text("".join(out))
print(f"copied {len(lines)} lines minus {end-start} ggiraph lines = {len(out)}")
PY
grep -nE "^   [0-9]\." post/styles.css
```
Expected: sections 1, 2, 4, 5, 6, 8 remain; no section 7. (The reference file has no section 3; that gap is preserved.)

- [ ] **Step 6: Append the new rules to `post/styles.css`**

```css

/* ==========================================================================
   9. Reference list
   ========================================================================== */

.reference-list ol {
  font-size: 0.88em;
  line-height: 1.55;
  padding-left: 1.4em;
}

/* Clear the fixed 44px progress header when a superscript jumps to a ref. */
.reference-list ol li {
  margin-bottom: 0.7em;
  scroll-margin-top: 60px;
}

/* Briefly tint the reference that was just jumped to. */
.reference-list ol li:target {
  background: #dbeafe;
  border-radius: 4px;
  box-shadow: 0 0 0 6px #dbeafe;
}
```

- [ ] **Step 7: Write the `.qmd` front matter and author block**

`cyp-inhib-blog-post.qmd` — body added in Tasks 3-7:

```markdown
---
title: "Lowering Inhibitions, One CYP at a Time: Building the OpenADMET CYP Inhibition and TDI Dataset"
date: "August 24, 2026"
format:
  html:
    output-file: index.html
    include-in-header:
      - text: |
          <meta property="og:title" content="Lowering Inhibitions, One CYP at a Time" />
          <meta property="og:description" content="How we built the OpenADMET CYP inhibition and time-dependent inhibition dataset across CYP1A2, CYP2C9, CYP2D6 and CYP3A4." />
          <meta property="og:image" content="https://openadmet.github.io/octant-cyp-inhib-blog-post/post/assets/og-preview.png" />
          <meta property="og:url" content="https://openadmet.github.io/octant-cyp-inhib-blog-post/" />
          <meta property="og:type" content="article" />
          <meta name="twitter:card" content="summary_large_image" />
          <meta name="twitter:title" content="Lowering Inhibitions, One CYP at a Time" />
          <meta name="twitter:description" content="How we built the OpenADMET CYP inhibition and time-dependent inhibition dataset across CYP1A2, CYP2C9, CYP2D6 and CYP3A4." />
          <meta name="twitter:image" content="https://openadmet.github.io/octant-cyp-inhib-blog-post/post/assets/og-preview.png" />
---

:::{.doc-authors}
Lauren Orr,
Scott Simpkins [{{< ai orcid color=#a6ce39 >}}](https://orcid.org/0000-0002-5997-2838),
Hugo MacDermott-Opeskin [{{< ai orcid color=#a6ce39 >}}](https://orcid.org/0000-0002-7393-7457),
Naomi Handly,
Pat Walters
:::
```

One author per line, so adding a missing ORCID is a one-line edit: append `` [{{< ai orcid color=#a6ce39 >}}](https://orcid.org/<ID>) `` before that line's comma.

- [ ] **Step 8: Render and run the test**

```bash
quarto render && ./scripts/check_post.sh
```
Expected: render succeeds, `PASS -- all assertions held`.

- [ ] **Step 9: Commit**

```bash
git add _quarto.yml .quartoignore .gitignore post/styles.css cyp-inhib-blog-post.qmd scripts/check_post.sh
git commit -m "Add Quarto scaffolding for the blog post

_quarto.yml mirrors the reference repo's HTML format (lux + styles.css
overlay, left ToC, lightbox, progress header) minus what does not apply here:
no execute/knitr blocks since the post has no code cells, and no ggiraph
fullscreen JS or CSS since there are no ggiraph widgets.

check_post.sh is the test harness; later tasks extend it."
```

---

### Task 3: Prose, headings, escapes and subscripts

**Files:**
- Modify: `cyp-inhib-blog-post.qmd`, `scripts/check_post.sh`

**Interfaces:**
- Consumes: `scratch/CYP Inhibition Blog Post.md` lines 6-113 (prose; lines 116-126 are base64 image definitions and are ignored entirely).
- Produces: the ten `##`/`###` headings that Tasks 4-7 attach content under.

**Reference:** source word counts are **4015** for lines 1-115 and **3772** for the body (lines 6-98, Introduction through Conclusion). The rendered body must land within 2% of 3772 — the check below enforces it, so no paragraph can be silently dropped.

- [ ] **Step 1: Add the failing assertions to `scripts/check_post.sh`**

Insert before the final `echo`/summary block:

```bash
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
```

**Per-heading `id=` assertions rather than an h2 total.** Only five of the seven `h2`s exist after this task; References arrives in Task 5 and Acknowledgements plus Data Accessibility in Task 7. Asserting a total of 7 here would leave the harness red through Tasks 3-6, training the implementer to ignore it. Individual `id=` assertions are additive, so each task's harness run is green when that task is done. Task 7 adds the `h2` total once all seven exist.

- [ ] **Step 2: Run to confirm the new assertions fail**

```bash
./scripts/check_post.sh
```
Expected: the `== prose ==` block reports failures; the `== scaffolding ==` block still passes.

- [ ] **Step 3: Transcribe the prose**

Copy the body text from `scratch/CYP Inhibition Blog Post.md` into the `.qmd` below the author block, applying exactly these transformations:

**Headings** — bold-only lines become real headings:

| Source | Line | Becomes |
|---|---|---|
| `**Introduction**` | 6 | `## Introduction` |
| `**Background**` | 10 | `## Background` |
| `**Assay Design**` | 20 | `## Assay Design` |
| `**Discussion**` | 56 | `## Discussion` |
| `**Assay Effect Sizes**` | 58 | `### Assay Effect Sizes` |
| `**Tiering strategy**` | 68 | `### Tiering strategy` |
| `**Calling TDI**` | 80 | `### Calling TDI` |
| `**3\. Conclusion**` | 94 | `## Conclusion` |

`**![][image6]**` (line 76) is a **bolded image, not a heading** — it becomes a normal figure block in Task 4. Do not turn it into a heading.

`**References**` (100) and `**Acknowledgements**` (108) become `## References` / `## Acknowledgements` in Tasks 5 and 7.

**Escapes** — unescape throughout: `\<` `\>` `\[` `\]` `\-` `\~` `\.` `\(` `\)`. E.g. `\<$1/well` becomes `<$1/well`, `\~72%` becomes `~72%`, `\> log10(2)` becomes `> log10(2)`.

**Subscripts** — in the "Calling TDI" prose (source lines 82-92) the Docs export flattened subscripts. Restore as HTML:

| Source | Becomes |
|---|---|
| `pIC50TDI\_condition` | `pIC50<sub>TDI condition</sub>` |
| `pIC50CI\_lower,TDI\_condition` | `pIC50<sub>CI lower, TDI condition</sub>` |
| `pIC50CI\_upper,direct\_condition` | `pIC50<sub>CI upper, direct condition</sub>` |
| `ΔpIC50CI\_lower` | `ΔpIC50<sub>CI lower</sub>` |

Leave the numbered list at source lines 84-86 (the three TDI-calling methods) as a markdown ordered list. Leave `**Figure 1**`-style inline bold cross-references as they are — they are prose, not headings.

**Do not** add, drop, reword or reorder prose. Citation superscripts are Task 5; figure blocks are Task 4. Leave the `\[insert interactive figure\]` marker (line 90) in place for Task 6.

- [ ] **Step 4: Verify no prose was lost**

```bash
python3 - <<'PY'
import re, pathlib
src = pathlib.Path("scratch/CYP Inhibition Blog Post.md").read_text().splitlines()
body = " ".join(src[5:98])                       # lines 6-98, Introduction..Conclusion
qmd  = pathlib.Path("cyp-inhib-blog-post.qmd").read_text()
qmd  = qmd.split("---", 2)[-1]                   # drop front matter
def words(s):
    s = re.sub(r'<[^>]+>', ' ', s)               # strip HTML tags
    s = re.sub(r'[#*`\[\]()_\\|]', ' ', s)       # strip markdown punctuation
    return len(s.split())
a, b = words(body), words(qmd)
print(f"source body {a} words / qmd {b} words / delta {(b-a)/a*100:+.1f}%")
assert abs(b-a)/a < 0.02, "prose drifted more than 2% -- something was dropped or duplicated"
print("OK")
PY
```
Expected: `OK`, delta within +/-2%. (At this point the `.qmd` has no figure captions or references yet, so expect a delta near zero; re-run after Tasks 4-7 and the delta will go positive as captions land.)

- [ ] **Step 5: Render and run the test**

```bash
quarto render && ./scripts/check_post.sh
```
Expected: the `== prose ==` block passes in full. Later tasks add their own assertions; nothing here is left red.

- [ ] **Step 6: Commit**

```bash
git add cyp-inhib-blog-post.qmd scripts/check_post.sh
git commit -m "Add the post prose with real headings and restored subscripts

Bold pseudo-headings from the Google Docs export become h2/h3 so the ToC
works. Unescapes the export's backslash artifacts and restores the flattened
pIC50 subscripts in the Calling TDI section. Drops the orphaned '3.' from the
Conclusion heading. A word-count check guards against dropped paragraphs."
```

---

### Task 4: Figures 1-6

**Files:**
- Modify: `cyp-inhib-blog-post.qmd`, `scripts/check_post.sh`

**Interfaces:**
- Consumes: Task 1's `post/figures/figureN.webp`; Task 2's `.figure-caption` / `.figure-toc` CSS; Task 3's headings.
- Produces: six `#### Figure N: ... {.figure-toc}` headings, extending the ToC.

- [ ] **Step 1: Add the failing assertions**

```bash
echo
echo "== static figures =="
want_n "webp img tags"        6 "$HTML" '<img src="post/figures/figure[1-6]\.webp"'
want_n "figure-toc headings"  6 "$HTML" '<h4 class="figure-toc'   # Task 6 bumps this to 7
want_n "figure-caption divs"  6 "$HTML" 'class="figure-caption"'   # Task 6 bumps this to 7
want_n "lightbox anchors"     6 "$HTML" 'class="[^"]*lightbox'
want "Figure 1 caption lead"    "$HTML" '<strong>Figure 1:</strong>'
want "Figure 6 caption lead"    "$HTML" '<strong>Figure 6:</strong>'
absent "no italic captions left" "$QMD" '^\*Figure [0-9]'
```

**Both count patterns are scoped to a single tag on purpose.** `lightbox: true` renders
each figure as `<a href="...webp"><img src="...webp">`, so an unscoped path pattern
matches twice per figure; and pandoc's `section-divs` copies heading classes onto the
wrapping `<section>`, so an unscoped `figure-toc` matches twice per heading. Anchoring
to `<img src=` and `<h4 class=` counts the real things once each.

**Count-assertion rule:** a count line lives in the harness exactly once. When a
later task changes the expected number, it **edits that line in place** — it never
appends a second assertion for the same pattern, which would guarantee one of the
two always fails. Task 6 bumps this `figure-toc` count from 6 to 7 that way.

- [ ] **Step 2: Run to confirm failure**

```bash
./scripts/check_post.sh
```
Expected: the `== static figures ==` block fails (0 of 6 everywhere).

- [ ] **Step 3: Replace each image reference with a figure block**

For each of the six, replace the `![][imageN]` line **and** the italic caption line that follows it. Figure 1 (source lines 26-28) in full, as the pattern:

```markdown
#### Figure 1: Assay workflow {.figure-toc}

![](post/figures/figure1.webp)

:::{.figure-caption}
**Figure 1:** Workflow for running the CYP inhibition assay. The general procedure and reagents were adapted from the Thermo Vivid P450 Assay kit, but we adapted it to 1536 well-scale and designed a two-armed approach to assess TDI. Assay arms will be discussed in more depth later in this post.
:::
```

Note: the trailing `4` on `kit4` is citation 4 and is handled in Task 5 — transcribe the caption without it for now.

Short titles for the `{.figure-toc}` headings:

| N | Source lines | Short title |
|---|---|---|
| 1 | 26-28 | Assay workflow |
| 2 | 34-36 | Fluorogenic probes and spectra |
| 3 | 38-40 | Coumarin probe optimization |
| 4 | 48-50 | Direct vs. time-dependent inhibition |
| 5 | 64-66 | Assay effect sizes |
| 6 | 76-78 | Tiering strategy |

Rules for every block:
- The source caption is wrapped in `*...*` italics. **Drop the italics** — `.figure-caption` already styles the text. Keep any *inner* emphasis (e.g. `*in vitro*`).
- Rewrite the leading `Figure N\.` as a bold `**Figure N:**` lead, matching the reference repo.
- Unescape as in Task 3 (`Figure 4\.` -> `Figure 4:`, `\~1500` -> `~1500`).
- Figure 6's source line is `**![][image6]**`; drop the surrounding bold entirely.

- [ ] **Step 4: Render and run the test**

```bash
quarto render && ./scripts/check_post.sh
```
Expected: the `== static figures ==` block fully passes.

- [ ] **Step 5: Confirm the ToC gained the figure entries**

```bash
grep -oE '#figure-[a-z0-9-]+' _site/index.html | sort -u
```
Expected: six distinct figure anchors.

- [ ] **Step 6: Commit**

```bash
git add cyp-inhib-blog-post.qmd scripts/check_post.sh
git commit -m "Add figures 1-6 with captions and hidden ToC headings

Each figure gets a {.figure-toc} h4 that CSS hides in the body but surfaces
in the sidebar ToC on scroll, matching the reference repo. Captions move from
source italics into .figure-caption divs with a bold 'Figure N:' lead."
```

---

### Task 5: Citations and the reference list

**Files:**
- Modify: `cyp-inhib-blog-post.qmd`, `scripts/check_post.sh`

**Interfaces:**
- Consumes: Task 2's `.cite-tip` and `.reference-list` CSS; Task 3's prose; Task 4's Figure 1 caption.
- Produces: `## References` (the 6th of 7 `h2`s) and the `#ref-1`..`#ref-5` anchor targets.

Five references, each cited exactly once. **No `bibliography:` key is set, so citeproc stays off and nothing collides with the References heading.**

- [ ] **Step 1: Add the failing assertions**

```bash
echo
echo "== citations =="
want_n "cite-tip anchors"    5 "$HTML" 'class="cite-tip"'
want_n "cite-tip tooltips"   5 "$HTML" 'data-tooltip="[^"]+"'
want_n "reference list items" 5 "$HTML" 'id="ref-[1-5]"'
want "reference-list wrapper"  "$HTML" 'class="[^"]*reference-list'
want "References heading"      "$HTML" 'id="references"'
want "CYP1A2 not CYP1A23"      "$HTML" 'CYP2C9, and CYP1A2<'
absent "no glued citation digits" "$QMD" 'post1|GSTs2|CYP1A23|kit4|TDI5'
```

The `CYP2C9, and CYP1A2<` assertion is the guard for the trap on source line 18.

- [ ] **Step 2: Run to confirm failure**

```bash
./scripts/check_post.sh
```
Expected: the `== citations ==` block fails.

- [ ] **Step 3: Replace the five inline markers**

Each marker is a digit glued to the end of the preceding word. Replace **only** these five occurrences:

| Source | Line | Replace with |
|---|---|---|
| `post1` | 8 | `post<a href="#ref-1" class="cite-tip" data-tooltip="Walters, P. (2026). Do Our CYP Structural Alerts Actually Work? OpenADMET.">1</a>` |
| `GSTs2` | 12 | `GSTs<a href="#ref-2" class="cite-tip" data-tooltip="Zhao, M.; Ma, J.; Li, M. et al. (2021). Cytochrome P450 Enzymes and Drug Metabolism in Humans. International Journal of Molecular Sciences.">2</a>` |
| `CYP1A23` | 18 | `CYP1A2<a href="#ref-3" class="cite-tip" data-tooltip="Zanger, U. M.; Schwab, M. (2013). Cytochrome P450 enzymes in drug metabolism: regulation of gene expression, enzyme activities, and impact of genetic variation. Pharmacology &amp; Therapeutics.">3</a>` |
| `kit,` (see note) | 28 | `kit<a href="#ref-4" class="cite-tip" data-tooltip="Life Technologies (2012). Vivid CYP450 Screening Kits User Guide. Thermo Fisher Scientific.">4</a>,` |
| `TDI5` | 46 | `TDI<a href="#ref-5" class="cite-tip" data-tooltip="Berry, L. M.; Zhao, Z. (2008). An examination of IC50 and IC50-shift experiments in assessing time-dependent inhibition of CYP3A4, CYP2D6 and CYP2C9 in human liver microsomes. Drug Metabolism Letters.">5</a>` |

**Note on citation 4 — its source string no longer exists.** Task 4 transcribed Figure 1's
caption *without* the trailing digit, so the `.qmd` now reads `...Thermo Vivid P450 Assay
kit,` and `grep -c kit4` returns **0**. Insert the anchor between `kit` and the comma.
This is the one citation that lands inside a `.figure-caption` div rather than body prose,
so it is also the one that legitimately changes a caption Task 4 verified — expected.

**Traps — do not touch any of these:**
- `CYP1A23` on line 18 is `CYP1A2` + citation `3`. Getting this wrong silently renames an enzyme.
- `EC50`, `IC50`, `pIC50`, `log10`, `log2`, `CYP3A4`, `CYP2D6`, `CYP2C9`, `CYP1A2`, `CYP2J2`, `1536`, `DDS10`, and catalog numbers (`P2856`, `PV6140`, `O-13873-r1`) are **not** citations.
- Line 22 mentions "Vivid CYP fluorescence kits (ThermoFisher)" with **no** marker. Do not add one. Add no citation absent from the source.
- Ampersands inside `data-tooltip` must be `&amp;` (reference 3).

- [ ] **Step 4: Add the References section**

Replacing source lines 100-106, placed after `## Conclusion`:

```markdown
## References

:::{.reference-list}
<ol>
<li id="ref-1">Walters P. Do Our CYP Structural Alerts Actually Work? OpenADMET [blog]. August 11, 2026. <a href="https://openadmet.ghost.io/do-our-cyp-structural-alerts-actually-work/">openadmet.ghost.io</a></li>
<li id="ref-2">Zhao M, Ma J, Li M, Zhang Y, Jiang B, Zhao X, Huai C, Shen L, Zhang N, He L, Qin S. Cytochrome P450 Enzymes and Drug Metabolism in Humans. <em>Int J Mol Sci.</em> 2021;22(23):12808. PMID 34884615. <a href="https://pmc.ncbi.nlm.nih.gov/articles/PMC8657965/">PMC8657965</a></li>
<li id="ref-3">Zanger UM, Schwab M. Cytochrome P450 enzymes in drug metabolism: regulation of gene expression, enzyme activities, and impact of genetic variation. <em>Pharmacol Ther.</em> 2013;138(1):103-141. <a href="https://doi.org/10.1016/j.pharmthera.2012.12.007">doi:10.1016/j.pharmthera.2012.12.007</a></li>
<li id="ref-4">Life Technologies. Vivid CYP450 Screening Kits User Guide. Protocol part no. O-13873-r1 (MAN0003095). Rev. 24 April 2012. <a href="https://documents.thermofisher.com/TFS-Assets/LSG/brochures/VividScreeningKitManual24Apr20121.pdf">PDF</a></li>
<li id="ref-5">Berry LM, Zhao Z. An examination of IC50 and IC50-shift experiments in assessing time-dependent inhibition of CYP3A4, CYP2D6 and CYP2C9 in human liver microsomes. <em>Drug Metab Lett.</em> 2008;2(1):51-59. PMID 19356071. <a href="https://pubmed.ncbi.nlm.nih.gov/19356071/">PubMed</a></li>
</ol>
:::
```

Reference 4's long catalog-number list from the source is trimmed to the protocol part number; the linked PDF carries the full list.

- [ ] **Step 5: Render and verify every anchor resolves**

```bash
quarto render
python3 - <<'PY'
import re, pathlib
h = pathlib.Path("_site/index.html").read_text()
hrefs = re.findall(r'class="cite-tip"[^>]*href="#(ref-\d)"', h) + \
        re.findall(r'href="#(ref-\d)"[^>]*class="cite-tip"', h)
ids = set(re.findall(r'id="(ref-\d)"', h))
print("cite-tip targets:", sorted(set(hrefs)))
print("reference ids:   ", sorted(ids))
missing = sorted(set(hrefs) - ids)
assert not missing, f"dangling citation anchors: {missing}"
assert len(hrefs) == 5, f"expected 5 cite-tips, found {len(hrefs)}"
assert "CYP1A23" not in h, "line-18 trap: CYP1A2 got renamed to CYP1A23"
print("OK -- 5 citations, all anchors resolve")
PY
./scripts/check_post.sh
```
Expected: `OK -- 5 citations, all anchors resolve`, and the `== citations ==` block passes.

- [ ] **Step 6: Commit**

```bash
git add cyp-inhib-blog-post.qmd scripts/check_post.sh
git commit -m "Add citation tooltips anchored to a reference list

The five inline markers from the Docs export were digits glued to the
preceding word. Each becomes a .cite-tip superscript with a hover card, in the
reference repo's style, that also anchors to a retained numbered list. Note
line 18's 'CYP1A23' was CYP1A2 plus citation 3; a check guards it."
```

---

### Task 6: The interactive figure

**Files:**
- Modify: `cyp-inhib-blog-post.qmd`, `post/styles.css`, `_quarto.yml` (after-body script), `scripts/check_post.sh`

**Interfaces:**
- Consumes: the committed `figures/embed/` (6 files, ~70 MB) and Task 2's `resources:` entry.
- Produces: Figure 7, the 7th `{.figure-toc}` heading.

**Sizing, computed from the figure's own source — do not guess:**

| Component | Source | px |
|---|---|---|
| facet grid | `src/app.js:97` `W=360`, 2 cols + 8px gap | 728 |
| detail panel | `src/styles.css:41` `width:506px` | 506 |
| `main` padding (12x2) + gap (12) | `src/styles.css:30` | 36 |
| **natural width** | | **1270** |

`src/styles.css:30` is `main{display:flex; gap:12px; padding:12px; flex-wrap:wrap}` — the facet grid sits **beside** the detail panel, not above it. Below ~1270px the flex container wraps and height nearly doubles. Natural height at full width is ~963px: controls ~141 + `main` padding 24 + `max(facets 768, detail ~798)`.

- [ ] **Step 1: Add the failing assertions**

```bash
echo
echo "== interactive figure =="
want "iframe present"           "$HTML" '<iframe[^>]*figures/embed/index\.html'
want "iframe lazy"              "$HTML" '<iframe[^>]*loading="lazy"'
want "full-bleed wrapper"       "$HTML" 'figure-fullbleed'
want "open-in-tab escape link"  "$HTML" 'figure-escape'
want "autosize script"          "$HTML" 'fullbleedAutosize'
# Per the count-assertion rule, EDIT the existing count lines in place — do not
# append rival assertions. Figure 7 adds BOTH a figure-toc heading and a
# figure-caption div, so two counts go 6 -> 7:
#   sed -i '' 's/want_n "figure-toc headings"  6/want_n "figure-toc headings"  7/' scripts/check_post.sh
#   sed -i '' 's/want_n "figure-caption divs"  6/want_n "figure-caption divs"  7/' scripts/check_post.sh
# The other two Task 4 counts stay at 6: Figure 7 is an iframe, so it adds no
# <img src=...webp> and no lightbox anchor.
want "Figure 7 caption lead"    "$HTML" '<strong>Figure 7:</strong>'
absent "placeholder marker gone" "$QMD" 'insert interactive figure'

for f in index.html RDKit_minimal.wasm figure_detail_CYP1A2.json \
         figure_detail_CYP2C9.json figure_detail_CYP2D6.json figure_detail_CYP3A4.json; do
  if [[ -f "_site/figures/embed/$f" ]]; then printf '  ok   resource %s\n' "$f"
  else printf '  FAIL resource %s missing from _site\n' "$f"; fails=$((fails+1)); fi
done
```

- [ ] **Step 2: Run to confirm failure**

```bash
./scripts/check_post.sh
```
Expected: the `== interactive figure ==` block fails.

- [ ] **Step 3: Add the CSS**

Append to `post/styles.css`:

```css

/* ==========================================================================
   10. Full-bleed interactive figure
   ========================================================================== */

/* The embedded figure needs 1270px to lay its facet grid beside its 506px
   detail panel (src/app.js:97 W=360; src/styles.css:41). Narrower than that and
   its `main` flex container wraps, doubling the height. So break out of the
   850px body column: 1360px clears 1270 with room for a scrollbar, and still
   fits a 1440px viewport without horizontal scroll. */
.figure-fullbleed {
  width: min(96vw, 1360px);
  margin-left: 50%;
  transform: translateX(-50%);
  margin-top: 2em;
  margin-bottom: 0.5em;
}

.figure-fullbleed iframe {
  display: block;
  width: 100%;
  /* Fallback only. The autosize script replaces this with the iframe's real
     scrollHeight. ~963px is the computed natural height; 1000 adds slack. */
  min-height: 1000px;
  border: 1px solid #e0e0e0;
  border-radius: 6px;
  background: #fff;
}

.figure-escape {
  font-size: 0.85em;
  text-align: right;
  margin-bottom: 0.4em;
}
```

- [ ] **Step 4: Add the autosize script to `_quarto.yml`**

Append inside the existing `include-after-body` `<script>` block, before its closing `</script>`:

```javascript
            // Size the full-bleed iframes to their content. Both documents are
            // served from the same origin, so the parent can read the child's
            // scrollHeight -- no change to the embedded figure required. Over
            // file:// this read is blocked and the CSS min-height applies.
            (function fullbleedAutosize() {
              var frames = document.querySelectorAll('.figure-fullbleed iframe');
              if (!frames.length) return;
              function fit(f) {
                try {
                  var d = f.contentDocument;
                  if (!d || !d.documentElement) return;
                  var h = Math.max(d.documentElement.scrollHeight, d.body ? d.body.scrollHeight : 0);
                  if (h > 0) f.style.height = (h + 2) + 'px';
                } catch (e) { /* cross-origin: keep the CSS fallback */ }
              }
              frames.forEach(function(f) {
                f.addEventListener('load', function() { fit(f); });
                if (f.contentDocument && f.contentDocument.readyState === 'complete') fit(f);
              });
              var t;
              window.addEventListener('resize', function() {
                clearTimeout(t);
                t = setTimeout(function() { frames.forEach(fit); }, 150);
              });
            })();
```

- [ ] **Step 5: Replace the placeholder with the figure block**

**Two lines must be replaced, not one.** The marker in the `.qmd` is
`[insert interactive figure]` — no backslashes, since Task 3's unescaping stripped them —
on line 136. **Line 138 holds the un-transformed Figure 7 caption**
(`**Figure 7. Interactive visualization of the dose-response curves...**`), because Task 3
transcribed source line 92 as ordinary body prose. Replace **both** lines with the block
below; leaving line 138 in place would render two Figure 7 captions. Note the source uses
`Figure 7.` with a period — the block below uses the `**Figure 7:**` colon form, matching
figures 1-6:

```markdown
#### Figure 7: TDI-shift explorer {.figure-toc}

::: {.figure-fullbleed}
<p class="figure-escape"><a href="figures/embed/index.html" target="_blank" rel="noopener">Open the explorer in a new tab &#8599;</a></p>
<iframe src="figures/embed/index.html" title="Interactive CYP TDI-shift explorer" loading="lazy"></iframe>
:::

:::{.figure-caption}
**Figure 7:** Interactive visualization of the dose-response curves in the training dataset. 6897 compounds were selected for dose-response follow-ups across one or multiple enzymes. In every plate, each enzyme was tested against one literature-annotated TDI control and one non-TDI control (labeled "control"), and, with the exception of CYP2C9, another literature-annotated compound (either TDI or non-TDI, labeled "literature"). The scatterplots compare the pIC50s measured in the time-dependent vs. direct inhibition conditions, with the distance above the y=x line being the observed pIC50 shift caused by time-dependent inhibition. A point is colored red if the chosen method calls that molecule as a time-dependent inhibitor, and gray if not. Mousing over a scatterplot point reveals (top to bottom) the molecule's structure, information on how it was screened, an overlaid plot of the raw data and dose-response curve fits for the two conditions, exact pIC50 and shift values, and a detailed view of the posterior distribution of the two pIC50s (Methods 1 and 2) or the pIC50 shift (Method 3).
:::
```

Per the global constraints, `figures/embed/` and `src/` are **not** modified. The embedded page keeps its own `<h1>`, class toggles, method selector and theme toggle — it is a self-contained tool.

- [ ] **Step 6: Render and confirm the resources copied**

```bash
quarto render
ls -la _site/figures/embed/
du -sh _site
```
Expected: all 6 files present, byte sizes matching `figures/embed/`; `_site` ~70 MB.

**The `figures/embed/**` glob is already confirmed working** — Task 2 added it and all six
files are present in `_site/figures/embed/` today, so this step should pass without
intervention. The fallback below is contingency only; do not apply it pre-emptively.

**If `_site/figures/embed/` is empty or missing**, the glob did not resolve. Fall back to a post-render copy — add to `_quarto.yml` under `project:`:

```yaml
  post-render:
    - scripts/copy_embed.sh
```

and create `scripts/copy_embed.sh`:

```bash
#!/usr/bin/env bash
# Quarto's resources glob can miss the embed payload; copy it explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p _site/figures/embed
cp -R figures/embed/. _site/figures/embed/
echo "copied $(ls _site/figures/embed | wc -l | tr -d ' ') files into _site/figures/embed/"
```

- [ ] **Step 7: Run the test**

```bash
./scripts/check_post.sh
```
Expected: the `== interactive figure ==` block passes, including all 6 resource checks.

- [ ] **Step 8: Verify the real rendered height in a browser**

Serve over HTTP — `file://` blocks the same-origin height read:

```bash
(cd _site && python3 -m http.server 8765) &
sleep 2
```

Open `http://localhost:8765/`, scroll to Figure 7, and in the devtools console:

```javascript
var f = document.querySelector('.figure-fullbleed iframe');
console.log('iframe box:', f.getBoundingClientRect().width, 'x', f.getBoundingClientRect().height);
console.log('content:', f.contentDocument.documentElement.scrollHeight);
console.log('main wrapped?', getComputedStyle(f.contentDocument.querySelector('#detail')).width);
```

Expected: iframe width >= 1270 at a normal desktop window; iframe height tracks content height (not stuck at 1000); `#detail` width `506px`. Confirm visually that the facet grid and detail panel are **side by side**, and that hovering a scatterplot point populates the structure, DRC and posterior panels. Then `kill %1`.

- [ ] **Step 9: Commit**

```bash
git add cyp-inhib-blog-post.qmd post/styles.css _quarto.yml scripts/check_post.sh
git commit -m "Embed the interactive TDI-shift figure as a full-bleed iframe

The figure needs 1270px to put its facet grid beside its 506px detail panel
(src/app.js:97 W=360, src/styles.css:41); narrower and its flex container
wraps and the height doubles. So the wrapper breaks out of the 850px body
column to min(96vw, 1360px), and a same-origin script sizes the iframe from
the child's scrollHeight rather than hardcoding a height. The embedded figure
itself is unchanged."
```

---

### Task 7: Closing sections and footer

**Files:**
- Modify: `cyp-inhib-blog-post.qmd`, `scripts/check_post.sh`

**Interfaces:**
- Consumes: Task 2's `.doc-version` CSS.
- Produces: `## Acknowledgements` and `## Data Accessibility` (completing the 7 `h2`s).

- [ ] **Step 1: Add the failing assertions**

```bash
echo
echo "== closing sections =="
want_n "h2 sections (all 8 now)" 8 "$HTML" '<h2 class="anchored"'
want "Acknowledgements heading" "$HTML" 'id="acknowledgements"'
want "Data Accessibility"       "$HTML" 'id="data-accessibility"'
want_n "doc-version rows"     2 "$HTML" 'class="doc-version"'
want "last-updated line"        "$HTML" 'Last updated: August 24, 2026'
want "github source link"       "$HTML" 'github\.com/OpenADMET/octant-cyp-inhib-blog-post'
want "dataset not-yet-released" "$HTML" 'not yet publicly available|forthcoming'
absent "no fake dataset link"   "$HTML" 'huggingface\.co/datasets/openadmet/Octant_CYP_inhibition'
```

The last assertion matters: the reference repo links a HuggingFace dataset. **This** post's export is not published, so do not copy that link across.

The `doc-version` pattern is scoped to the exact class. An unscoped
`[^"]*doc-version[^"]*` also matches the `.doc-version-left` and `.doc-version-right`
children, counting 6 where two rows exist — verified with a test render.

- [ ] **Step 2: Run to confirm failure**

```bash
./scripts/check_post.sh
```

- [ ] **Step 3: Add the Acknowledgements section**

Transcribed from source lines 108-113, unescaped:

```markdown
## Acknowledgements

The authors would like to acknowledge experimental data, analysis and scientific input contributed by **Ayesha Ghazali, Ana Lindahl, Robert Warneford-Thompson, Sean Colby and Nathan Abell** for this blog post.

This work was supported by funding from ARPA-H and the Astera Foundation.

We would also like to acknowledge technical support for our CYP assay development from SCIEX and Discovery Life Sciences.
```

- [ ] **Step 4: Add Data Accessibility and the footer**

Modeled on the reference repo, but honest about the unpublished dataset:

```markdown
## Data Accessibility

Blog post source code, the interactive figure, and the methods behind it are on
**[GitHub](https://github.com/OpenADMET/octant-cyp-inhib-blog-post)**. The underlying
dose-response parquet export is not yet publicly available; a public release is forthcoming.

::::{.doc-version}
:::{.doc-version-left}
Last updated: August 24, 2026
:::
:::{.doc-version-right}
Built with ❤️ and [Quarto](https://quarto.org)
:::
::::

::::{.doc-version}
:::{.doc-version-left}
© 2026 OpenADMET
:::
:::{.doc-version-right}
Code licensed [Apache 2.0](https://github.com/OpenADMET/octant-cyp-inhib-blog-post/blob/main/LICENSE) · Data licensed [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
:::
::::
```

**Note:** this links a `LICENSE` file that does not exist in this repo yet — Task 8 adds it.

- [ ] **Step 5: Render and run the test**

```bash
quarto render && ./scripts/check_post.sh
```
Expected: all blocks pass, including the newly added `h2 sections (all 8 now)`.

**Why 8 and not 7:** this task adds *two* h2 sections — `## Acknowledgements` and
`## Data Accessibility` — on top of the six that exist after Task 5 (Introduction,
Background, Assay Design, Discussion, Conclusion, References).

**Why `class="anchored"` and not a bare `<h2`:** Quarto emits `<h2 id="toc-title">`
for the sidebar ToC heading, so a bare tag count runs one high. `class="anchored"`
is emitted on content headings only — verified in the rendered output.

- [ ] **Step 6: Confirm this task only appended**

Do **not** re-run Task 3's word-count drift check here. That check hard-asserts a
+/-2% band against the prose-only source range (lines 6-98), which was the right
test when the `.qmd` held nothing but that prose. Tasks 4-7 legitimately add
captions, the reference list and the footer — measured at **+47%** — so the band
cannot hold and the assertion fires by design. It is not a regression signal any
more; its job was done in Task 3, and the export's digest in
`post/PROSE-SOURCE.sha256` is what guards fidelity from here.

The invariant that *is* meaningful for this task is that nothing above the new
sections moved:

```bash
REFLINE=$(grep -n '^## References' cyp-inhib-blog-post.qmd | cut -d: -f1)
git show <BASE>:cyp-inhib-blog-post.qmd | head -n "$REFLINE" > /tmp/before_head.txt
head -n "$REFLINE" cyp-inhib-blog-post.qmd > /tmp/after_head.txt
diff /tmp/before_head.txt /tmp/after_head.txt && echo "byte-identical up to ## References"
```

Expected: empty diff. Everything from the front matter through the reference list
is untouched, and this task is a pure append.

- [ ] **Step 7: Commit**

```bash
git add cyp-inhib-blog-post.qmd scripts/check_post.sh
git commit -m "Add acknowledgements, data accessibility and footer

Data Accessibility says the parquet export is not yet public rather than
copying the reference repo's HuggingFace link, which points at a different
dataset."
```

---

### Task 8: CI, licence and documentation

**Files:**
- Create: `.github/workflows/render-deploy.yml`, `CLAUDE.md`, `LICENSE`
- Modify: `README.md`

**Interfaces:**
- Consumes: everything above.
- Produces: the deployed site.

- [ ] **Step 1: Write the workflow**

`.github/workflows/render-deploy.yml`:

```yaml
on:
  workflow_dispatch:
  push:
    branches: main

name: Quarto Publish

jobs:
  build-deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: write

    steps:
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Set up Quarto
        uses: quarto-dev/quarto-actions/setup@v2

      - name: Render
        run: quarto render

      # force_orphan matters: without it, every deploy adds another copy of the
      # ~70 MB figures/embed payload to gh-pages history.
      - name: Publish to gh-pages
        uses: peaceiris/actions-gh-pages@v4
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: _site
          force_orphan: true
```

No R and no Python setup, unlike the reference repo's workflow: this post has no code cells, and the figure pipeline cannot run in CI anyway because its parquet input lives in gitignored `scratch/`.

- [ ] **Step 2: Validate the workflow YAML parses**

```bash
python3 -c "import yaml,sys; d=yaml.safe_load(open('.github/workflows/render-deploy.yml')); print('steps:', [s.get('name') for s in d['jobs']['build-deploy']['steps']])"
```
Expected: `steps: ['Check out repository', 'Set up Quarto', 'Render', 'Publish to gh-pages']`.

- [ ] **Step 3: Add the LICENSE referenced by the footer**

```bash
cp /Users/scott/Octant/software/Octant_CYP_blog_post/LICENSE LICENSE
head -3 LICENSE && wc -l LICENSE
```
Expected: Apache License 2.0, **191 lines**. (The footer added in Task 7 links this path.)

- [ ] **Step 4: Correct the README's data-staging section and add render docs**

In `README.md`, the `## Data` section currently opens:

> The figure is built from a published parquet dataset, ~237 MB. It is **not committed here** — you have to stage it locally before anything below will run.
> ### Staging it
> Download the dataset and unpack it into `scratch/` so the layout is:

**Two edits, not one.** The section opens by calling it "a **published** parquet
dataset" (line 8) — that claim is false and contradicts the replacement below,
five lines later. Drop the word `published` from line 8 as well, so the section is
internally consistent. Then replace "Download the dataset and unpack it into
`scratch/`" with wording that does not promise a download that does not exist:

```markdown
The dataset is **not yet published**, so there is no download URL and no fetch
script in this repo. If you have a copy, unpack it into `scratch/` so the layout is:
```

Then add a new section after `## Build`:

```markdown
## Blog post

The post is a Quarto document rendered to static HTML and published to GitHub Pages
at <https://openadmet.github.io/octant-cyp-inhib-blog-post/>.

    quarto render                            # -> _site/index.html
    cd _site && python3 -m http.server 8765  # preview at localhost:8765

Requires Quarto >= 1.4 (for `lightbox`). Rendering executes **no** code — the prose
is static, the six static figures are committed webp, and the interactive figure is
the prebuilt `figures/embed/` payload copied in as a Quarto resource. So neither R
nor Python is needed to render, and CI installs only Quarto.

Preview over HTTP, not `file://`: the interactive figure's iframe is auto-sized by
reading its own `scrollHeight`, which the browser blocks across `file://` origins.

Static figure assets are regenerated from PNG exports in `scratch/` with:

    ./scripts/make_figure_assets.sh

Assertions over the rendered output:

    ./scripts/check_post.sh
```

- [ ] **Step 5: Write `CLAUDE.md`**

```markdown
# CLAUDE.md — CYP Inhibition & TDI Blog Post

Scientific blog post and interactive figure for the OpenADMET Octant CYP inhibition
and time-dependent inhibition (TDI) dataset. Rendered with [Quarto](https://quarto.org/).

**Publication date:** August 24, 2026
**Site:** https://openadmet.github.io/octant-cyp-inhib-blog-post/
**Styled after:** `OpenADMET/Octant_CYP_blog_post`

---

## The two halves of this repo

**1. The interactive figure** (predates the post; treat as stable)

`src/` -> `build.py` -> `figures/embed/`. A D3 + RDKit-wasm page showing the Bayesian
pEC50 shift across CYP1A2/2C9/2D6/3A4. Built from a ~237 MB parquet export staged in
gitignored `scratch/data/`, via `scripts/build_figure_data.R` -> `build/*.json`.

    Rscript scripts/build_figure_data.R   # parquet -> build/*.json  (~3 min)
    python3 build.py                      # -> figures/embed/   (what the post embeds)
    python3 build.py --standalone         # one self-contained HTML

`figures/embed/` is **committed** (~70 MB) because CI cannot rebuild it: the parquet
input is not in the repo. R deps: DBI, dbplyr, digest, dplyr, duckdb, jsonlite,
posterior, tidyr. `build.py` is stdlib-only — there is no Python dependency to install.

**2. The blog post** (this layer)

    quarto render                            # -> _site/index.html
    cd _site && python3 -m http.server 8765  # preview
    ./scripts/check_post.sh                  # assertions over _site/

`cyp-inhib-blog-post.qmd` is **hand-written** — unlike the reference repo's, it is not
assembled by a script. Prose came from a Google Docs markdown export in `scratch/`.

---

## Gotchas

- **Rendering executes no code.** No `execute:`/`knitr:` blocks, no code cells. Neither
  R nor Python is needed to render, so CI installs only Quarto.
- **`scratch/` is gitignored**, so `post/figures/*.webp` are committed derived files.
  Regenerate with `./scripts/make_figure_assets.sh`.
- **Preview over HTTP, never `file://`.** The Figure 7 iframe is auto-sized by a script
  reading its own same-origin `scrollHeight`; `file://` blocks that read and the page
  falls back to a 1000px min-height.
- **The Figure 7 iframe has a hard 1270px width floor** — the facet grid (`src/app.js:97`,
  W=360, 2 cols) beside the 506px detail panel (`src/styles.css:41`). Below that,
  `main{flex-wrap:wrap}` drops the panel underneath and the height doubles. Hence
  `.figure-fullbleed { width: min(96vw, 1360px) }`.
- **`{.figure-toc}` h4 headings are invisible by design** — CSS hides them in the body
  and surfaces them in the sidebar ToC on scroll.
- **Citations are hand-rolled**, not citeproc. `.cite-tip` anchors with `data-tooltip`
  point at `#ref-N` list items. No `bibliography:` key is set. Ampersands inside
  `data-tooltip` must be `&amp;`.
- **`_site/` is gitignored.** Nothing needs it tracked: the static figures are committed
  webp and the interactive figure is the committed `figures/embed/` payload, so CI can
  reproduce `_site` from what is in the repo.
- **R dependencies are not currently locked.** Task 9 (renv) is deferred and blocked
  on a lockfile from the machine that ran the pipeline, so `renv.lock`, `.Rprofile`
  and `renv/` are absent. The pipeline needs `DBI`, `dbplyr`, `digest`, `dplyr`,
  `duckdb`, `jsonlite`, `posterior`, `tidyr`, plus `testthat` for the suite.
  Rendering the post needs none of it — CI never runs R.
- **No DOI yet.** Do not add a DOI badge until there is one.
- **Missing ORCIDs:** Lauren Orr, Naomi Handly, Pat Walters. One author per line in the
  `.doc-authors` block, so each is a one-line edit.

---

## Deploy

Push to `main` -> `.github/workflows/render-deploy.yml` renders and publishes `_site`
to `gh-pages` with `force_orphan: true`. Orphaning is deliberate: without it every
deploy would add another copy of the ~70 MB figure payload to that branch's history.
Ghost points at the Pages URL.
```

- [ ] **Step 6: Verify the docs match reality**

Check **every present-tense claim** in `CLAUDE.md` and the new `README.md` sections
against the repo: do the named paths exist, are the sizes right, and does anything
describe a file that has not been created yet? Task 9's renv files are the obvious
trap — they do not exist.

```bash
# No Python-packaging references: this repo has none, and implying otherwise
# would send a reader looking for a pyproject.toml that does not exist.
for f in CLAUDE.md README.md; do
  n=$(grep -cE 'pyproject|uv\.lock|uv sync|uv add' "$f" || true)
  echo "$f: $n python-packaging references (want 0)"
done
./scripts/check_post.sh
git diff --stat bdf24c3 -- src/ R/ tests/ build.py data/ \
  scripts/build_figure_data.R scripts/verify_data.sh
```

The grep is anchored to real tokens (`pyproject`, `uv.lock`, `uv sync`, `uv add`)
rather than a bare `uv`, which would match inside ordinary words.
Expected: no Python-packaging references, `check_post.sh` passes, and **empty** diff output — proving the figure pipeline is untouched.

- [ ] **Step 7: Commit**

```bash
git add .github CLAUDE.md LICENSE README.md
git commit -m "Add deploy workflow, licence and repo documentation

CI installs Quarto only: the post has no code cells, and the figure pipeline
cannot run there anyway since its parquet input is gitignored. force_orphan
keeps gh-pages from accumulating a copy of the ~70 MB figure payload per
deploy.

Corrects the README's data section, which told readers to download a dataset
that is not published anywhere."
```

- [ ] **Step 8: Push and confirm the deploy**

```bash
git push -u origin convert-to-quarto
```

Then open a PR to `main`. The workflow triggers on push to `main`, so the site
deploys on merge. **After merging**, enable Pages if it is not already on:
repo Settings -> Pages -> Source: "Deploy from a branch" -> `gh-pages` / `/ (root)`.
Then check the run in the Actions tab and load
<https://openadmet.github.io/octant-cyp-inhib-blog-post/>.

---

### Task 9: renv lockfile — BLOCKED on author input

**Files:**
- Create: `renv.lock`, `.Rprofile`, `renv/activate.R`, `renv/settings.json`, `renv/.gitignore`, `.renvignore`

**Interfaces:**
- Consumes: a `renv.lock` produced on the machine that ran the figure pipeline.
- Produces: reproducible R environment for `scripts/build_figure_data.R` and `tests/`.

**This task is deliberately last and blocks nothing.** Every task above ships without it.

**Why it cannot be done on the dev machine:** `duckdb` and `posterior` are not installed
locally, so `renv::snapshot()` would silently omit two of the eight dependencies, and
`Rscript -e 'testthat::test_dir("tests/testthat")'` aborts at `helper-source.R:4`
(`library(duckdb)`) before running a single test. The lockfile must come from the
machine where the pipeline actually ran.

- [ ] **Step 1: Obtain the lockfile from the build machine**

On the machine that ran `scripts/build_figure_data.R`, in the repo root:

```r
renv::init(bare = TRUE)   # if renv is not yet initialised there
renv::snapshot()
```

Then confirm all eight packages plus `testthat` are captured:

```bash
python3 -c "
import json; d=json.load(open('renv.lock'))
need={'DBI','dbplyr','digest','dplyr','duckdb','jsonlite','posterior','tidyr','testthat'}
have=set(d['Packages']); missing=need-have
print('R version:', d['R']['Version']); print('packages:', len(have))
print('MISSING:', missing or 'none')
assert not missing
"
```
Expected: `MISSING: none`.

- [ ] **Step 2: Add `.renvignore`**

Keeps renv's dependency scanner out of directories with no R code:

```
scratch
_site
figures
src
docs
```

- [ ] **Step 3: Verify `.Rprofile` does not break rendering**

`renv::init()` writes `.Rprofile` containing `source("renv/activate.R")`. Rendering
must remain R-free:

```bash
quarto render && ./scripts/check_post.sh
```
Expected: unchanged pass. If Quarto starts probing R, add `engine: markdown` to the
`.qmd` front matter to pin it to the null engine.

- [ ] **Step 4: Document and commit**

Add to `README.md` under `## Tests`:

```markdown
R dependencies are locked with [renv](https://rstudio.github.io/renv/). Restore them
with `renv::restore()` before running the build or the tests. Rendering the blog post
needs neither R nor renv.
```

```bash
git add renv.lock .Rprofile renv .renvignore README.md
git commit -m "Lock R dependencies for the figure pipeline with renv

Covers the build and test path only; rendering the post executes no code, so
CI does not restore this."
```

---

## Post-implementation verification

- [ ] `quarto render` completes with no warnings
- [ ] `./scripts/check_post.sh` reports `PASS -- all assertions held`
- [ ] `git diff --stat bdf24c3 -- src/ R/ tests/ build.py data/ scripts/build_figure_data.R scripts/verify_data.sh` is empty
- [ ] Served over HTTP: ToC populates and reveals figure entries on scroll; progress header slides in past 300px and its bar tracks scroll; citation hover cards appear; clicking a superscript jumps to and highlights the right reference; lightbox opens each figure with its caption; Figure 7's facet grid and detail panel sit side by side and hovering a point populates structure, DRC and posterior panels
- [ ] Author's server: `renv::restore()` then the documented `PASS 99 / FAIL 0 / SKIP 0` from the R suite, with the parquet staged

## Known open items

Carried from the spec; each is stated rather than guessed:

1. **DOI** — none exists; no badge shipped.
2. **ORCIDs** for Lauren Orr, Naomi Handly, Pat Walters — author supplying.
3. **`figure4.png` is 928x646**, far below its siblings (3000-7350px). Not upscaled; it
   will look soft in the lightbox. A higher-resolution re-export is the fix.
4. **Dataset unpublished** — no fetch script; README and Data Accessibility say so.
