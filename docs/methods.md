# Methods

How the figure's numbers are computed, from the published parquet to the JSON
the page renders. Ported from `DESIGN.md` §4 of the source project
(`openadmet/cyp-inhibition/2_bayesian-shift-viz/`) and updated for this
pipeline, which reads a pre-computed parquet export rather than the `brms`
fit objects directly — the posterior draws already exist as rows in
`draws/`; this repo only summarizes and reshapes them (`R/figure_data.R`,
`R/stats_shift.R`, `R/kde.R`, `R/blob.R`).

## 1. Data

Each compound is screened under two preincubation conditions —
**inactive** (`inactive_preincubation`, baseline potency) and **active**
(`active_preincubation`, with an active enzyme system) — fit as **two
independent `brms` models**, one per condition. There is no shared or
hierarchical structure between them; independence is what makes elementwise
draw subtraction and a product-form joint density valid below.

The join key is `(run, pair_id)` — `pair_id` restarts at 1 in every run, so
`run` must be part of the key. The dataset covers **6,896 compound pairs
across ten runs**: 1,500 / 1,337 / 1,584 / 2,475 for CYP1A2 / CYP2C9 / CYP2D6
/ CYP3A4 respectively.

The potency parameter is **pEC50** (posterior mean and central-95% CI, the
`posterior`/`brms` default: mean + q2.5/q97.5). Its prior has a hard floor at
**pEC50 = 1**, which matters for the density estimates below.

### Compound classes: assay role vs. TDI annotation

Every compound carries a `compound_class` in the published parquet, but that
value names the compound's **operational role in the assay**, not its TDI
behaviour. The export pipeline (`openadmet/cyp-inhibition/3_blog-data-export`)
publishes the semantic TDI annotation alongside it, as a separate
`tdi_annotation` column keyed on **both** `compound_class` and `enzyme` (the
"Other Control" literature set means something different per enzyme):

| Raw `compound_class` | Enzyme | Label shown in the figure | n |
|---|---|---|---|
| `Library` | any | `Unknown` | 6,526 |
| `Process Control` | any | `TDI (control)` | 132 |
| `Positive Control` | any | `Non-TDI (control)` | 132 |
| `Other Control` | `CYP1A2`, `CYP3A4` | `TDI (literature)` | 76 |
| `Other Control` | `CYP2D6` | `Non-TDI (literature)` | 30 |

**Naming trap:** the assay's `Positive Control` is the positive control for
reversible enzyme *inhibition*, not for TDI — it is in fact the **non-TDI**
control. `Process Control` is the TDI control. Anyone comparing this figure
against the raw pipeline output needs to know this, or the two read
backwards.

`CYP2C9` has no `Other Control` rows at all — a real gap in the assay design
for that enzyme, not missing data, so no label is defined for that
combination.

`Unknown` means "no annotated TDI behaviour," which is what the library
compounds are — it is not a claim that they were tested and came back
negative.

### Compound identity: common names and deck membership

Every compound carries `compound_id` (an internal `OCNT-` identifier), and
some carry two further fields sourced from outside the assay data itself:
`compound_name`, a human-readable common name, and `compound_deck`, which
Enamine catalogue the compound was purchased from.

`compound_name` is resolved from two sources, with the first taking
precedence on overlap:

1. **A curated map of the eleven assay reference compounds** (the TDI and
   Non-TDI controls, both `Process`/`Positive Control` and `Other Control`
   literature sets) — recovered from each compound's published
   `standardized_smiles` and confirmed against its InChIKey and molecular
   formula. The experimentalist signed off on all eleven names on
   2026-08-12.
2. **Enamine vendor names for the rest of the library**, joined by
   Z-number: each compound's batch id resolves to its Enamine catalogue
   number, which is looked up in a committed, point-in-time-scraped cache of
   Enamine's own product names.

Vendor names ship as-is. Enamine's catalogue is the authority on what a
compound is called, including its salt form, so nothing is stripped or
reinterpreted from the structure — an earlier version of this pipeline did
that (a tiered counterion-stripping system plus a structural cross-check),
and it produced three rounds of silent mislabels before being removed. The
only edit applied to a vendor name today is a ten-entry map correcting
Enamine's own typos (`SPELLING_FIXES` in `py/compound_names.py`, settled by
an audit of all 307 live vendor names); every other name, counterions and
brand marks included, passes through unchanged.

`compound_deck` is deck membership — `Enamine FDA-Approved` or `Enamine
Discovery Diversity` — on the same Z-number join, against the two vendor
catalogue files that list Z-numbers per deck. It is independent of naming:
a compound can have a deck with no name (Discovery Diversity has no common
names to give at all) or a name with no deck (the reference compounds,
which were never purchased from either Enamine deck).

**Coverage, measured against the current build:** 317 of 4,916 distinct
compounds are named (796 of 6,896 index rows), and 4,324 of 4,916 are
deck-annotated (5,963 of 6,896 index rows). Naming is **partial by
design** — Discovery Diversity is novel chemistry with no common name to
give, and even within the FDA-Approved deck, complete coverage was never a
requirement (a compound can lack a resolvable Z-number, or have a
Z-number absent from the name cache). Adding these two fields grows
`figure_index.json` by about 443 KB, from roughly 2.98 MB to 3.43 MB.

**The structure column.** The `smiles` field in the index and detail JSON is
sourced from `cxsmiles`, not `standardized_smiles`. `standardized_smiles` is
not used because it damages structures: it reduces cisplatin to a bare
`[Pt+2]`, strips propranolol's HCl, and drops the enhanced-stereochemistry
annotation (`|&1:...|`) on 198 compounds — the record that those centres are
racemic or unresolved rather than the specific enantiomer drawn. `cxsmiles`
keeps all of that: multi-fragment salts and coordination complexes, and the
CX extension blocks that record stereochemistry the plain SMILES can't.

The annotation is a transcription of the TDI annotations from the
experimentalist who ran these runs — domain knowledge, not something
derivable from the data — computed once in the export pipeline
(`tdi_annotation()` in that repo's `R/tdi_annotation.R`) and published as a column,
rather than recomputed here. `compound_summary()` in `R/figure_data.R` simply
reads `tdi_annotation` from `compounds.parquet` and exposes it as the
`compound_class` field the index JSON and page already key on — one source
of truth for the mapping. The export pipeline's mapping fails loudly on any
`(compound_class, enzyme)` pair the table above doesn't cover, rather than
silently falling through to `Unknown`; controls still keep their internal
`OCNT-` identifiers, same as library compounds — the annotation is additive,
it does not replace `compound_class`.

## 2. Point estimates and marginal credible intervals

**A note on naming.** The dataset column, and this document throughout, use
`pEC50`, which is what the upstream fits emit. The figure labels the same
quantity **pIC50**, since the assay measures inhibition and that is the term a
reader of the post expects. Same number, different label; nothing is
transformed between the parquet and the axis.

For each compound × condition, summarize the 4,000 posterior draws of pEC50:
mean, and the 2.5%/97.5% quantiles as the 95% credible interval. Computed in
SQL (`compound_summary()` in `R/figure_data.R`) via duckdb over the `draws`
table, grouped by `(run, pair_id, condition)`.

The Hill slope is summarized the same way, but note the units differ between
the dataset and the figure. The model fits and the parquet store it as
`SlopeLog2`, i.e. log2 of the slope; the detail panel reports `2^x`, the Hill
slope itself, because that is the unit a reader expects. Exponentiating the
2.5%/97.5% quantiles is exact — `2^x` is monotone, so it maps the interval
without distortion — while exponentiating the mean yields the geometric mean,
which is the appropriate central estimate for a parameter estimated on a log
scale. Across the dataset the reported Hill slopes run 0.62 to 2.88, median
1.12.

## 3. Shift

The shift is the **elementwise difference of the two conditions' draws**,
valid because the two fits are independent:

```
shift = pEC50(active) − pEC50(inactive)
```

This requires pairing individual draws, not just subtracting summary
statistics, so the join is on `(run, pair_id, chain, iteration)` — the
sampler's own draw identity — never aggregated first. Report `mean`,
`q2.5`, `q97.5` of the resulting distribution the same way as the marginals.
A positive shift means the compound is more potent when pre-incubated with
an active enzyme system — the signature of time-dependent inhibition (TDI).

## 4. Hit-calling: three modes

Whether a compound counts as a TDI "hit" is a judgment call with more than
one reasonable definition, so the figure exposes **three modes** rather than
baking in one verdict. Both thresholds are reader-adjustable at runtime
(defaults: shift threshold `log10(2)` ≈ 0.301, i.e. a 2× potency change;
active-pEC50 threshold `4.3`), and the calls below are what those defaults
currently give across the dataset:

**The potency threshold applies to mode 1 only.** The two interval modes
deliberately ignore it: an interval test already requires the shift to be
resolved against its own uncertainty, so a weak compound cannot pass on noise,
and adding a potency floor on top would discard well-resolved shifts for being
low-potency — a different question from whether the shift is real. The
`active pEC50 >` control is disabled, and its guide line hidden, outside mode 1.

1. **Thresholds only** (default) — the shift clears the shift threshold
   *and* the active-condition pEC50 clears the potency threshold.
   **1,332 compounds** at the defaults.
2. **Disjoint 95% CIs** — the shift clears the shift threshold *and* the two
   conditions' 95% credible intervals do not overlap. **1,281 compounds** at
   the defaults. Not nested in mode 1: 49 of these sit below the potency
   threshold (active pEC50 3.75–4.30) with intervals that are nonetheless
   cleanly separated.
3. **Bayesian shift interval** — the shift's own 95% credible interval must
   lie entirely above zero (`shift.mean > shift threshold` and
   `shift.q2.5 > 0`). **1,437 compounds** at the defaults.

Mode 2 is contained in mode 3 across this dataset — all 1,281 — but that is an
empirical result, not a theorem, and it is worth being precise about why.
Testing the difference directly is generally more sensitive than asking whether
two marginal intervals clear each other, so the containment is what one expects.
It is not guaranteed. Writing `a` for the active condition's 2.5% quantile and
`b` for the inactive condition's 97.5%, mode 2 says `a > b`; then
`{shift ≤ 0} ⊆ {A ≤ a} ∪ {I ≥ b}`, so a union bound gives
`P(shift ≤ 0) ≤ 0.05` — while mode 3 demands `< 0.025`. Disjoint marginals buy
only half the guarantee mode 3 asks for, leaving a band in which mode 2 passes
and mode 3 fails.

Under normal-theory intervals no such compound can exist for *any* correlation
`ρ`, since the shift's SD is `√(sₐ² + sᵢ² − 2ρsₐsᵢ) ≤ sₐ + sᵢ` with equality
only at `ρ = −1`. Escaping that needs both asymmetric posteriors — live here,
because these are empirical MCMC quantiles rather than normal-theory intervals —
and strong negative dependence between the two conditions. Neither is present:
the shift interval is narrower than the summed marginal widths for every one of
the 6,896 compounds (median ratio 0.72, maximum 0.959), nowhere near the
`ρ = −1` boundary, and the nearest mode-2 compound to failing mode 3 sits at
`shift.q2.5 = +0.080`.

No verdict is precomputed and stored: the figure's inputs
(`shift.{mean,lo,hi}`, `active.pEC50`, `active.{lo,hi}`, `inactive.{lo,hi}`)
are exactly what every mode needs, and nothing else — a baked-in flag would
go stale the moment a reader moves a threshold slider.

## 5. Marginal densities

Each condition's pEC50 posterior is summarized as a 1-D density for the
detail panel, via Gaussian KDE (`kde_reflected()` in `R/kde.R`) evaluated on
a shared grid spanning both conditions. Because the pEC50 prior has a hard
floor at 1, a naive KDE would leak density mass below the floor and (after
renormalizing) fake a second mode near it. Reflection avoids this: draws are
mirrored across the floor (`2·floor − draws`) before the Gaussian kernel is
applied, then density outside `[floor, ∞)` is zeroed and the result
renormalized on the grid. Bandwidth is `stats::bw.nrd0`, floored at `1e-3` to
avoid degenerate near-zero bandwidths for compounds whose draws are almost
all pinned at the floor.

## 6. Joint credible region ("blob")

Because the two conditions are independent, their **joint density is the
outer product of the two boundary-corrected marginal KDEs**:
`f[i, j] = f_x[i] · f_y[j]`, evaluated on a finer grid than the marginal
panel (`joint_blob()` in `R/blob.R`). The 95% highest-density region is
calibrated by **Hyndman's (1996) density-quantile rule**: sort the grid
densities descending, accumulate probability mass (density × cell area)
until it reaches 0.95, and take that density value as the contour level.
`grDevices::contourLines()` at that level gives one or more closed polygons.
A naive fixed-level 2-D density contour (e.g. `geom_density_2d` defaults) is
*uncalibrated* and is not used for this reason.

Because the fits are independent, the blob is axis-aligned by construction —
any visible tilt would be a finite-sample KDE artifact, not signal. Where the
contour yields multiple polygons, sub-percent fragments that are grid noise
rather than a genuine second mode are dropped (`drop_specks()`: any polygon
under 2% of the largest polygon's area is discarded, unless dropping would
leave nothing).

## 7. Dose-response curves

The DRC sub-plot overlays both conditions' fitted curves (point-estimate
normalized activity vs. concentration) with the raw well-level points. Each
condition's pEC50 is drawn as a vertical dashed line at
`conc = 10^(−pEC50_mean)`, with a shaded band over
`[10^(−q97.5), 10^(−q2.5)]` — note the interval flips orientation, since a
higher pEC50 is a lower concentration.

**The pEC50 credible interval is the only uncertainty drawn on this panel.**
The published curves themselves carry point estimates only (no per-point
response-level draws), so there is nothing to build a response-level ribbon
from; the credible band on the pEC50 line is the one place genuine posterior
uncertainty about *this* panel's quantity is available and is shown.
