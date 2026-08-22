# Design: Quarto blog post for the CYP inhibition / TDI dataset

**Date:** 2026-08-19
**Status:** approved design, pre-implementation
**Reference implementation:** `OpenADMET/Octant_CYP_blog_post` (colleague's repo; match its style)

---

## 1. Goal

Turn this repo from "a repo that builds one interactive figure" into a Quarto-rendered
HTML blog post that embeds that figure, styled to match the reference repo, published
to GitHub Pages at `https://openadmet.github.io/octant-cyp-inhib-blog-post/` so Ghost
can point at it.

## 2. Non-goals

- **Do not modify the interactive figure.** `src/`, `build.py`, `R/`, `scripts/`,
  `tests/` are untouched. The figure was recently tuned; this work wraps it, not edits it.
- **No Python packaging.** `build.py` imports only stdlib (`argparse`, `base64`,
  `json`, `pathlib`, `shutil`), so there is nothing to lock. No `pyproject.toml`,
  no `uv.lock` — unlike the reference repo, which needs both.
- **No data-fetch script.** The 237 MB parquet export is not published anywhere yet.
- **No re-running the figure build in CI.** The parquet lives in gitignored `scratch/`,
  so CI cannot build the figure. It consumes the committed `figures/embed/` instead.

## 3. Inputs

| Input | Detail |
|---|---|
| `scratch/CYP Inhibition Blog Post.md` | 125 lines, ~4,000 words. Google Docs export. |
| `scratch/figure1..6.png` | 7350x4110, 6600x4800, 3600x3000, 928x646, 3000x2580, 2700x3900 |
| `figures/embed/` | Prebuilt figure: `index.html` (3.9 MB), 4 detail JSONs (12-21 MB), `RDKit_minimal.wasm` (6.9 MB). ~70 MB total, already tracked in git. |

**Figure mapping is verified.** The markdown's `![][imageN]` refs resolve to base64
PNGs that are Google Docs' 624px-wide downsampled previews. Decoding each IHDR and
comparing aspect ratio against `scratch/figureN.png` confirms `imageN` -> `figureN.png`
for all six, with the files in `scratch/` being 4-12x higher resolution. Use the files;
ignore the base64.

## 4. Target layout

```
cyp-inhib-blog-post.qmd            # the post, hand-written single file
_quarto.yml
post/
  styles.css                       # from reference repo, adapted
  figures/figure1..6.webp
  assets/openadmet-logo.png        # copied from reference repo
  assets/og-preview.png            # derived from figure 6
figures/embed/                     # unchanged, served as a Quarto resource
_extensions/schochastics/academicons/   # copied from reference repo (ORCID icons)
LICENSE                            # Apache 2.0, copied from reference repo
renv.lock, .Rprofile, renv/        # from Scott's build machine
.github/workflows/render-deploy.yml
CLAUDE.md                          # new
README.md                          # extended
R/ scripts/ tests/ data/ docs/ src/ build.py   # unchanged
```

## 5. `_quarto.yml`

Mirrors the reference, minus what does not apply:

- `project.output-dir: _site`, `render: [cyp-inhib-blog-post.qmd]`
- `project.resources:` the logo, the og image, and `figures/embed/` (so the ~70 MB
  interactive figure lands in `_site/figures/embed/`)
- `format.html`: `theme: [lux, post/styles.css]`, `grid.body-width: 850px`,
  `toc: true`, `toc-location: left`, `toc-expand: 2`, `toc-depth: 4`,
  `smooth-scroll: true`, `number-sections: false`, `lightbox: true`
- `include-before-body`: the fixed progress header (logo, title, reading-progress
  track) and the inline hero logo
- `include-after-body`: the reference's scroll JS — ToC-figure reveal on first scroll,
  progress-header show/hide + bar fill, and copying `.figure-caption` HTML into
  lightbox `data-description`. **Drop the ggiraph fullscreen-modal block**: there are
  no ggiraph widgets here.
- No `execute:`/`knitr:` blocks. The document has no code cells.

Progress-header title: "Lowering Inhibitions, One CYP at a Time".

## 6. Content transformation

The source is a Google Docs export and needs real editing, not a copy-paste.

### 6.1 Headings

Bold-only lines become real headings so the ToC works:

| Source line | Becomes |
|---|---|
| `**Introduction**` | `## Introduction` |
| `**Background**` | `## Background` |
| `**Assay Design**` | `## Assay Design` |
| `**Discussion**` | `## Discussion` |
| `**Assay Effect Sizes**` | `### Assay Effect Sizes` |
| `**Tiering strategy**` | `### Tiering strategy` |
| `**Calling TDI**` | `### Calling TDI` |
| `**3\. Conclusion**` | `## Conclusion` (drop the orphaned "3.") |
| `**References**` | `## References` |
| `**Acknowledgements**` | `## Acknowledgements` |

`**![][image6]**` (line 76) is a bolded image, not a heading — it becomes a normal
figure block.

### 6.2 Escape artifacts

Unescape the Docs export throughout: `\<` `\>` `\[` `\]` `\-` `\~` `\.` `\(` `\)`.
Verify none remain with a grep for backslash-punctuation before rendering.

### 6.3 Subscript notation

The Docs export flattens subscripts. Restore them as HTML in the "Calling TDI"
prose (source lines 82-92):

- `pIC50TDI\_condition` -> `pIC50<sub>TDI condition</sub>`
- `pIC50CI\_lower,TDI\_condition` -> `pIC50<sub>CI lower, TDI condition</sub>`
- `pIC50CI\_upper,direct\_condition` -> `pIC50<sub>CI upper, direct condition</sub>`
- `ΔpIC50CI\_lower` -> `ΔpIC50<sub>CI lower</sub>`
- `log`<sub>2</sub>-style cases elsewhere as they arise

### 6.4 Citations

Five references, each cited exactly once. Inline markers are digits glued to the
preceding word:

| Marker | Line | Reference |
|---|---|---|
| `post1` | 8 | Walters, "Do Our CYP Structural Alerts Actually Work?" |
| `GSTs2` | 12 | Zhao et al. 2021, Int J Mol Sci |
| `CYP1A23` | 18 | Zanger & Schwab 2013, Pharmacol Ther |
| `kit4` | 28 | Vivid CYP450 Screening Kits User Guide |
| `TDI5` | 46 | Berry & Zhao 2008, Drug Metab Lett |

Each becomes `<a href="#ref-N" class="cite-tip" data-tooltip="Author (Year). Title. Journal.">N</a>`
— the reference repo's blue pill-superscript with a hover card, but click-through to a
retained reference list.

**Traps:**
- `CYP1A23` is `CYP1A2` + citation 3. Do not read it as a number.
- `EC50`, `IC50`, `pIC50`, `log10`, `CYP3A4`, `CYP2D6`, `CYP2C9`, `CYP1A2`, `1536`,
  `DDS10`, `P2856`-style catalog numbers are **not** citations.
- Add no citations that are not in the source. Line 22 mentions the Vivid kits
  without a marker; leave it unmarked.

`## References` keeps the numbered list, each item carrying `id="ref-N"` so the
superscripts anchor to it. Written as raw `<ol>`/`<li id="ref-N">` inside a
`:::{.reference-list}` div. The div is the CSS hook rather than a `#references`
id, so nothing collides with Quarto's own citeproc handling of a References
heading. No `bibliography:` key is set, so citeproc stays off entirely.

### 6.5 Figures 1-6

Each `![][imageN]` plus its following italic caption becomes:

```
#### Figure N: <short title> {.figure-toc}

![](post/figures/figureN.webp)

:::{.figure-caption}
**Figure N:** <caption text, italics dropped, bolded lead>
:::
```

The `{.figure-toc}` heading is visually hidden by CSS and exists only to create the
ToC entry, exactly as in the reference repo. Short titles for all seven figures
(7 is used by section 6.7):

1. Assay workflow
2. Fluorogenic probes and spectra
3. Coumarin probe optimization
4. Direct vs. time-dependent inhibition
5. Assay effect sizes
6. Tiering strategy
7. TDI-shift explorer

### 6.6 Image conversion

`scratch/figureN.png` -> `post/figures/figureN.webp`: downscale to at most 2400px on
the long edge (no upscaling), then `cwebp -q 90`. 2400px keeps lightbox zoom sharp at
the ~1600px lightbox width while cutting the ~4 MB of PNG substantially.

`figure4.png` is only 928x646 and will not be upscaled; it will look softer than its
siblings. Flagged to the author — a higher-resolution re-export is the fix, outside
this work.

### 6.7 Figure 7 — the interactive figure

`\[insert interactive figure\]` (line 90) becomes:

```
#### Figure 7: TDI-shift explorer {.figure-toc}

::: {.figure-fullbleed}
<p class="figure-escape"><a href="figures/embed/index.html" target="_blank" rel="noopener">Open the explorer in a new tab &#8599;</a></p>
<iframe src="figures/embed/index.html" title="CYP TDI-shift explorer" loading="lazy"></iframe>
:::

:::{.figure-caption}
**Figure 7:** Interactive visualization of the dose-response curves ...
:::
```

**Sizing is driven by the figure's real layout, computed from its source.**
`src/styles.css:30` is `main{display:flex; gap:12px; padding:12px; flex-wrap:wrap}` —
the 2x2 facet grid sits *beside* a fixed-width detail panel, not above it:

| Component | Source | px |
|---|---|---|
| facet grid | `app.js:97` `W=360`, 2 cols + 8px gap | 728 |
| detail panel | `styles.css:41` `width:506px` | 506 |
| `main` padding (12x2) + gap (12) | `styles.css:30` | 36 |
| **natural content width** | | **1270** |

Below ~1270px `flex-wrap:wrap` drops the detail panel beneath the facets and the page
height nearly doubles. So:

- `.figure-fullbleed` breaks out of the 850px column to `min(96vw, 1360px)`, centred
  with symmetric negative margins. 1360 clears the 1270px floor with slack for a
  scrollbar, and is narrow enough to fit a 1440px viewport without horizontal scroll.
- **The iframe auto-sizes its height from the parent.** Both documents are served
  from the same origin, so a script in `include-after-body` reads
  `iframe.contentDocument.documentElement.scrollHeight` on the iframe's `load` event
  and on window `resize`, and sets `iframe.style.height`. This handles the wrapped
  layout on narrow viewports without touching the figure's source (see non-goals).
- CSS carries `min-height: 1000px` as the no-JS fallback. Derived from the source:
  controls ~141px + `main` padding 24px + `max(facets 768, detail ~798)` = ~963px.
- `loading="lazy"` so the ~59 MB of detail JSONs are not fetched until the reader
  scrolls near the figure.
- The embedded page keeps its own `<h1>`, class toggles, method selector and theme
  toggle. It is a self-contained tool; per non-goals it is not modified.
- Local preview must be over HTTP (`python -m http.server`), not `file://`, or the
  same-origin height read is blocked and the fallback min-height applies.

### 6.8 Front matter and closing sections

- `title:` "Lowering Inhibitions, One CYP at a Time: Building the OpenADMET CYP
  Inhibition and TDI Dataset"
- `date:` "August 24, 2026"
- `output-file: index.html`
- `include-in-header`: absolute `og:*` / `twitter:*` tags on
  `https://openadmet.github.io/octant-cyp-inhib-blog-post/`
- `.doc-authors` block: Lauren Orr, Scott Simpkins, Hugo MacDermott-Opeskin,
  Naomi Handly, Pat Walters. ORCID icons via the academicons extension for the two
  IDs sourced from the reference repo (Simpkins 0000-0002-5997-2838,
  MacDermott-Opeskin 0000-0002-7393-7457); the other three render as plain names
  until their ORCIDs are supplied.
- **No DOI badge.** The source says `DOI: XXXXX`; there is no DOI yet, so the badge
  is omitted rather than shipped with a placeholder.
- Closing sections modeled on the reference: `## Data Accessibility` linking the
  GitHub repo and stating the dataset release is forthcoming, plus two `.doc-version`
  footer rows (last-updated / built-with-Quarto, and copyright / license).

## 7. Styles

`post/styles.css` is the reference repo's file with:

- **Kept:** typography and spacing, title-block and `.doc-authors` / `.doc-version`,
  `.figure-caption`, ToC figure-entry rules, logo and progress header, `.cite-tip`
  tooltip.
- **Dropped:** section 7 in its entirety (ggiraph fullscreen) — no ggiraph here.
- **Added:** `.figure-fullbleed` / `.figure-escape` / iframe rules, and
  `.reference-list ol li` styling with `scroll-margin-top` so an anchored reference
  is not hidden under the fixed progress header.

## 8. Reproducibility

`renv.lock` (supplied from the build machine), `.Rprofile` and `renv/activate.R`
cover the figure pipeline's R dependencies: `DBI`, `dbplyr`, `digest`, `dplyr`,
`duckdb`, `jsonlite`, `posterior`, `tidyr`, plus `testthat`. This serves local
reproduction of the figure build and the test suite. It is deliberately **not** used
in CI, which never runs R.

**This step is blocked on an external input and is sequenced last.** The lockfile
must come from the machine that ran the pipeline; it cannot be generated here,
because `duckdb` and `posterior` are absent locally and `renv::snapshot()` would
silently omit them. Every other task is independent of it, so the post ships
without waiting.

## 9. CI and deploy

`.github/workflows/render-deploy.yml`, on push to `main` and `workflow_dispatch`:

1. `actions/checkout@v4`
2. `quarto-dev/quarto-actions/setup@v2`
3. `quarto render`
4. `peaceiris/actions-gh-pages@v4` — `publish_dir: _site`, `force_orphan: true`

`force_orphan` matters: without it every deploy adds another copy of the ~70 MB
figure payload to `gh-pages` history. Orphaning keeps that branch at one snapshot.

Sizes are within GitHub Pages limits — largest single file 21 MB (limit 100 MB),
site ~140 MB (soft limit 1 GB). The push is the slow step, ~1-2 min per deploy.

`.gitignore` gains: `/.quarto/`, `_freeze/`, `_site/`, `**/*.quarto_ipynb`,
`cyp-inhib-blog-post_files/`. `_site/` is **not** tracked; CI regenerates it from committed inputs on every push.
(The reference repo does not track its `_site/` either — its own CLAUDE.md claims it
does, three times, but that repo gitignores `_site/` and has never committed a file
under it. I had taken that claim at face value; it is stale documentation.)

## 10. Ghost integration

Ghost points at the Pages URL. The absolute `og:*` tags give correct link previews
when the URL is shared or embedded as a Ghost bookmark card.

## 11. Open items requiring author input

These are stated, not silently guessed:

1. **DOI** — none yet; badge omitted.
2. **ORCIDs** for Lauren Orr, Naomi Handly, Pat Walters.
3. **`figure4.png` resolution** — 928x646, visibly softer than the other five.
4. **Dataset location** — not published; `## Data Accessibility` says so rather than
   implying a download exists. `README.md:13` gets the same correction.

## 12. Verification

- `quarto render` completes with no warnings; `_site/index.html` exists.
- `_site/figures/embed/` contains all 6 files.
- Grep the rendered HTML: 5 `cite-tip` anchors, 5 `ref-N` ids, 7 `figure-toc`
  headings, 6 `<img>` webp figures, 1 iframe.
- Grep the `.qmd` for leftover backslash-escapes and `![][image` refs: zero hits.
- Serve `_site` locally and confirm: ToC populates, progress header appears on
  scroll, citation hover cards render, superscripts jump to the reference list,
  lightbox opens figures with captions, iframe loads and hover-detail works.
- **Figure pipeline untouched**, proven by diff rather than by tests:
  `git diff --stat bdf24c3 -- src/ R/ scripts/ tests/ build.py data/` is empty.
  The test suite cannot be the check here: `duckdb` and `posterior` are not
  installed on this machine, so `helper-source.R:4` aborts at `library(duckdb)`
  before any test runs, and `scratch/data/` (the parquet) is not staged either, so
  the regression tests would skip regardless. The README's documented
  PASS 99 / SKIP 0 is reproducible only on a machine with both the packages and
  the parquet.
