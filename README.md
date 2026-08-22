# Octant CYP TDI blog post

The OpenADMET blog post on CYP inhibition and time-dependent inhibition (TDI),
live at <https://openadmet.github.io/octant-cyp-inhib-blog-post/>.

Two halves, built and tested independently:

- **The post** — a Quarto document (`index.qmd`) rendered to static HTML. See
  [Blog post](#blog-post).
- **The interactive figure** — a 2×2 facet grid of the Bayesian pEC50 shift for
  CYP1A2, CYP2C9, CYP2D6 and CYP3A4, built from the parquet dataset below and
  embedded in the post as a prebuilt payload.

## Data

The figure is built from a parquet dataset, ~237 MB. It is **not
committed here** — you have to stage it locally before anything below will run.

### Staging it

The dataset is **not published yet**, so there is no download URL and no fetch
script in this repo. The well-level assay signals, and the per-compound posterior
samples of the inferred pIC50 and slope parameters that drive the figure, will be
available on request once the CYP inhibition challenge has concluded — that
gating is deliberate, so do not describe the data as available before then.

If you have a copy, unpack it into `scratch/` so the layout is:

    scratch/data/
      compounds/    drc_curves/   drc_points/
      draws/        drc_params/   MANIFEST.sha256

Then check it against the copy of the manifest committed in this repo:

    ./scripts/verify_data.sh          # expects 50 files, all OK

`scratch/` is gitignored, so nothing you put there will be committed.

`scratch/data/` is a convention, not a requirement, so **an empty `scratch/` does
not mean the data is gone.** A copy may already be sitting elsewhere on the
machine; look before you conclude anything is missing, and point the commands at
wherever it is rather than staging a second 237 MB copy. Both commands take a
path — but note they are **two different knobs**, because the build and the tests
are separate entry points:

    ./scripts/verify_data.sh /path/to/data
    Rscript scripts/build_figure_data.R --data /path/to/data
    CYP_DATA_DIR=/path/to/data Rscript -e 'testthat::test_dir("tests/testthat")'

Everything reads the parquet from the local filesystem; there is no support for
reading it over the network, and adding it would be a poor trade — a build reads
every posterior draw, which is most of the 237 MB.

### What is in it

Tables and their join key — note `pair_id` restarts at 1 in each run, so the
key is `(run, pair_id)`:

| Table | Contents |
|---|---|
| `draws/enzyme=<E>/run=<L>/` | 4,000 posterior draws per compound × condition: `pEC50`, `SlopeLog2` |
| `compounds/run=<L>/` | one row per compound × run: identity, class, structure |
| `drc_curves/run=<L>/` | fitted dose-response curves, 250 points per curve |
| `drc_points/run=<L>/` | raw well-level measurements |
| `drc_params/run=<L>/` | six DRC parameter summaries per curve |

## Build

    Rscript scripts/build_figure_data.R      # parquet -> build/*.json  (~3 min)
    python3 build.py                         # figures/embed/   — what the post embeds
    python3 build.py --standalone            # one self-contained HTML, opens from disk

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

The post's prose body was derived once from the Google Docs markdown export with
`scripts/build_post_body.py`; nothing runs it automatically. `--check` verifies and
writes nothing, while `--force` overwrites an edited body and would discard the
hand-authored figures, citations and closing sections, so leave it alone. The export
is gitignored, so its SHA-256 is recorded in `post/PROSE-SOURCE.sha256` to make drift
of that source detectable:

    cd scratch && shasum -a 256 -c ../post/PROSE-SOURCE.sha256   # or sha256sum -c

### Deploy

Pushing to `main` triggers `.github/workflows/render-deploy.yml`, which renders the
post and publishes `_site` to the `gh-pages` branch. Nothing needs building or
committing by hand — but note the deploy uses `force_orphan: true`, so `gh-pages`
is replaced rather than appended to. That is deliberate: `figures/embed/` is ~70 MB,
and without orphaning every deploy would add another copy of it to that branch's
history.

## Tests

R dependencies are locked with [renv](https://rstudio.github.io/renv/). Run
`renv::restore()` once before building the figure data or running the suite —
it installs the recorded versions into a project-local library. Rendering the
post needs neither R nor renv; see the note at the end of this section.

    Rscript -e 'renv::restore()'          # first time only
    Rscript -e 'testthat::test_dir("tests/testthat")'
    # expect: FAIL 0 | WARN 0 | SKIP 0 | PASS 99

The regression test (`tests/testthat/test-figure-regression.R`) compares the
built figure against the parquet it was built from, so it needs both
`build/*.json` (run `scripts/build_figure_data.R` first — `build/` is
gitignored) and the parquet itself. Staged at `scratch/data` as above, the
suite runs with no extra setup; if you keep the parquet elsewhere, point it
there with `CYP_DATA_DIR=/path/to/data`.

**A skipped test still reports green** (`testthat` prints `SKIP` separately
from `FAIL`, and an all-skip run is not a failure), so on a fresh clone with
neither `build/*.json` nor a parquet present, every regression test silently
skips and the suite still looks like it passed. Always check the reported
skip count is 0, not just that nothing failed.

`renv.lock` records R 4.5.2. All 50 pins resolve: 31 from current CRAN, 18 from
the CRAN archive (they are behind current CRAN, so those compile from source
rather than pulling binaries — expect the first restore to take a while), and
`posterior` 1.7.1 from the stan-dev r-universe, which the lockfile declares
alongside CRAN because CRAN only has 1.7.0. That one pin is the fragile one: an
r-universe serves only its latest build, so once stan-dev publishes a newer
`posterior` this lockfile will no longer restore that exact version. Nothing in
the figure pipeline depends on 1.7.1 specifically — if it breaks, re-pin to
whatever CRAN has and re-snapshot.

## Method

See `docs/methods.md`.
