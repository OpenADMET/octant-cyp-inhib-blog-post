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

`index.qmd` is **not assembled at render time** — unlike the reference
repo's, no script runs to build it. Its prose body was derived once from a Google Docs
markdown export in `scratch/` by `scripts/build_post_body.py`, which is wired into no
automation; the figures, captions, citations, reference list and closing sections were
authored directly in the file.

---

## Gotchas

- **Rendering executes no code.** No `execute:`/`knitr:` blocks, no code cells. Neither
  R nor Python is needed to render, so CI installs only Quarto.
- **`scratch/` is gitignored**, so `post/figures/*.webp` are committed derived files.
  Regenerate with `./scripts/make_figure_assets.sh`.
- **An empty `scratch/` does not mean the parquet is gone.** `scratch/data/` is just
  the default path, and because `scratch/` is gitignored nothing records whether a
  copy was ever put there. Look for one elsewhere on the machine before concluding
  the data is missing, then point `--data` (build) and `CYP_DATA_DIR` (tests) at it
  — two separate knobs — instead of staging another 237 MB copy. Check whatever you
  find against the committed manifest with `./scripts/verify_data.sh <path>`; it
  should report 50 files, all OK. Without the parquet the suite still reports green
  at `PASS 95 | SKIP 1`, so quote the skip count, never just the passes.
- **`scripts/build_post_body.py` can rewrite the prose body — do not run it with
  `--force`.** It derived the body once from the Google Docs export and runs in no
  automation. It refuses to overwrite a body that has been edited since it generated
  one; `--force` overrides that refusal and would discard everything hand-authored
  since (figure blocks, captions, citations, references, closing sections). `--check`
  verifies and writes nothing. The export itself lives in gitignored `scratch/` and so
  can never be committed, so the script records its SHA-256 in
  `post/PROSE-SOURCE.sha256` (same `sha256sum -c` format as `data/MANIFEST.sha256`) —
  that digest is the only way to detect the source prose drifting.
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
- **`_site/` is gitignored here.** Nothing needs it tracked: the six static
  figures are committed webp and the interactive figure is the committed
  `figures/embed/` payload, so there is no render-time step writing assets
  that Quarto can't reproduce on its own.
- **R dependencies are locked with renv; run `renv::restore()` before any R work.**
  `renv.lock` pins 50 packages against R 4.5.2. Rendering the post needs none of
  it — CI never runs R — so `.Rprofile` is inert during `quarto render`.
  Two things about that lockfile are deliberate and easy to "fix" wrongly:
  `posterior` is pinned to 1.7.1, which is ahead of CRAN's 1.7.0, so the
  lockfile declares the stan-dev r-universe alongside CRAN — do not drop that
  repo. And `_dependencies.R` exists only to be scanned: the suite calls bare
  `test_that()` and runs from the command line, so `testthat` is invisible to
  `renv::dependencies()` and falls out of the lockfile without it.
- **No DOI yet.** Do not add a DOI badge until there is one.
- **All four authors have ORCIDs** — Orr, Simpkins, MacDermott-Opeskin, Walters. One
  author per line in the `.doc-authors` block, so adding or changing one is a one-line
  edit. `check_post.sh` derives the expected count from the source rather than hardcoding
  it, and separately checks every ORCID shortcode carries a well-formed iD, so it adjusts
  on its own when the author list changes. Note iDs issued recently start `0009-`, not
  `0000-`, so never anchor a pattern on `0000`. Naomi Handly is credited in the
  Acknowledgements, not the author list.

---

## Deploy

Push to `main` -> `.github/workflows/render-deploy.yml` renders and publishes `_site`
to `gh-pages` with `force_orphan: true`. Orphaning is deliberate: without it every
deploy would add another copy of the ~70 MB figure payload to that branch's history.
Ghost points at the Pages URL.
