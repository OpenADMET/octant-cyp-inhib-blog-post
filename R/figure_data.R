# Reads the published parquet through duckdb. All of this layer is SQL: dbplyr
# emits it, duckdb runs it. Measured at 2.4 s for all 6,894 pairs.
suppressPackageStartupMessages({
  library(DBI); library(duckdb); library(dplyr); library(dbplyr)
})

open_data <- function(data_dir, threads = 8L) {
  con <- dbConnect(duckdb::duckdb())
  dbExecute(con, sprintf("SET threads=%d", threads))
  con
}

# hive_partitioning exposes the directory keys (enzyme, run) as columns.
parquet_tbl <- function(con, data_dir, table) {
  tbl(con, sql(sprintf(
    "SELECT * FROM read_parquet('%s/%s/**/*.parquet', hive_partitioning=true)",
    data_dir, table)))
}

draws_tbl     <- function(con, d) parquet_tbl(con, d, "draws")
compounds_tbl <- function(con, d) parquet_tbl(con, d, "compounds")
curves_tbl    <- function(con, d) parquet_tbl(con, d, "drc_curves")
points_tbl    <- function(con, d) parquet_tbl(con, d, "drc_points")

compound_summary <- function(con, data_dir) {
  dr <- draws_tbl(con, data_dir)

  marg <- dr %>%
    group_by(run, pair_id, condition) %>%
    summarise(mean  = mean(pEC50, na.rm = TRUE),
              lo    = quantile_cont(pEC50, 0.025),
              hi    = quantile_cont(pEC50, 0.975),
              # The detail header reports the Hill slope with a credible
              # interval, so carry its quantiles too, not just the mean.
              slope    = mean(SlopeLog2, na.rm = TRUE),
              slope_lo = quantile_cont(SlopeLog2, 0.025),
              slope_hi = quantile_cont(SlopeLog2, 0.975),
              .groups = "drop")

  wide <- marg %>%
    tidyr::pivot_wider(names_from = condition,
                       values_from = c(mean, lo, hi, slope, slope_lo, slope_hi)) %>%
    rename(inactive_mean = mean_inactive_preincubation,
           inactive_lo   = lo_inactive_preincubation,
           inactive_hi   = hi_inactive_preincubation,
           slope_inactive    = slope_inactive_preincubation,
           slope_inactive_lo = slope_lo_inactive_preincubation,
           slope_inactive_hi = slope_hi_inactive_preincubation,
           active_mean   = mean_active_preincubation,
           active_lo     = lo_active_preincubation,
           active_hi     = hi_active_preincubation,
           slope_active    = slope_active_preincubation,
           slope_active_lo = slope_lo_active_preincubation,
           slope_active_hi = slope_hi_active_preincubation)

  # The shift is elementwise over independent fits: join on (chain, iteration)
  # to reproduce the original pairing exactly. Never aggregate first.
  act <- dr %>% filter(condition == "active_preincubation") %>%
    select(run, pair_id, chain, iteration, pe_a = pEC50)
  ina <- dr %>% filter(condition == "inactive_preincubation") %>%
    select(run, pair_id, chain, iteration, pe_i = pEC50)

  shift <- inner_join(act, ina, by = c("run", "pair_id", "chain", "iteration")) %>%
    group_by(run, pair_id) %>%
    summarise(shift_mean = mean(pe_a - pe_i, na.rm = TRUE),
              shift_lo   = quantile_cont(pe_a - pe_i, 0.025),
              shift_hi   = quantile_cont(pe_a - pe_i, 0.975),
              .groups = "drop") %>%
    collect()

  # tdi_annotation is the semantic TDI label, computed once in the export
  # pipeline (openadmet/cyp-inhibition/3_blog-data-export, R/tdi_annotation.R)
  # and published as its own column -- one source of truth for the mapping.
  # Select it in as compound_class: that's the field every downstream
  # consumer (the build script, the index JSON, the page/JS) already keys
  # on, and the raw assay compound_class is not needed past this point.
  #
  # standardized_smiles is not used because it damages structures -- it
  # reduced cisplatin to a bare [Pt+2], stripped propranolol's HCl, and
  # dropped the enhanced-stereochemistry annotation (`|&1:...|`) on 198
  # compounds, which records that those centres are racemic or unresolved
  # rather than the specific enantiomer drawn. cxsmiles is exposed as
  # `smiles`, the name every downstream consumer (the build script, the
  # index JSON, the page) keys on.
  cmp <- compounds_tbl(con, data_dir) %>%
    select(enzyme, run, pair_id, compound_id, compound_class = tdi_annotation, plate,
           smiles = cxsmiles, compound_name, compound_deck) %>%
    collect()

  out <- cmp %>%
    inner_join(collect(wide), by = c("run", "pair_id")) %>%
    inner_join(shift, by = c("run", "pair_id"))

  # Significance is deliberately NOT computed here. The figure's two thresholds
  # (shift and active-pEC50) are user-adjustable at runtime, so any flag baked in
  # now would be stale the moment someone moves a slider. Every hit-calling mode
  # is derivable in JS from the columns above; keeping one source of truth for it
  # is the point.
  out[order(out$enzyme, out$run, out$pair_id), ]
}

GRID_N      <- 96L   # marginal / shift density grid
BLOB_GRID_N <- 140L  # finer grid for the 2-D contour
BLOB_PTS    <- 64L   # max vertices retained per contour polygon
PEC50_FLOOR <- 1     # prior floor; the KDE reflects across it

# Grids are arithmetic sequences, so store (lo, hi, n) rather than the array.
grid_spec <- function(lo, hi, n) list(lo = lo, hi = hi, n = n)

# The DRC panel draws each condition's pEC50 as a dashed vertical line with a
# shaded 95% band. The panel's x axis is concentration, so convert: a pEC50 of p
# is a concentration of 10^-p, which also flips the interval's orientation.
pec50_band <- function(mean, lo, hi) {
  list(line = 10^(-mean), band = c(10^(-hi), 10^(-lo)))  # ascending concentration
}

compound_detail <- function(draws_df, curves_df, points_df) {
  x <- draws_df$pEC50[draws_df$condition == "inactive_preincubation"]
  y <- draws_df$pEC50[draws_df$condition == "active_preincubation"]
  sx <- summ(x); sy <- summ(y)

  lo <- max(PEC50_FLOOR, min(x, y) - 0.5); hi <- max(x, y) + 0.5
  g  <- seq(lo, hi, length.out = GRID_N)
  fx <- kde_reflected(x, g, lower = PEC50_FLOOR)
  fy <- kde_reflected(y, g, lower = PEC50_FLOOR)

  bg   <- seq(min(x, y) - 0.8, max(x, y) + 0.8, length.out = BLOB_GRID_N)
  blob <- drop_specks(joint_blob(kde_reflected(x, bg, lower = PEC50_FLOOR),
                                 kde_reflected(y, bg, lower = PEC50_FLOOR),
                                 bg, bg, 0.95))
  blob <- lapply(blob, function(m) {
    m[downsample_idx(nrow(m), BLOB_PTS), , drop = FALSE]
  })

  # Elementwise over independent fits; draws_df is already in sampler order.
  s  <- y - x
  sg <- seq(min(s) - 0.3, max(s) + 0.3, length.out = GRID_N)

  cond_curve <- function(df, cond) {
    d <- df[df$condition == cond, , drop = FALSE]
    d <- d[order(d$conc_m), , drop = FALSE]
    # Also return this condition's own sorted distinct concentrations: the two
    # preincubation conditions can be fitted over different concentration
    # ranges for the same compound, so conc_key must be looked up (and stored)
    # per condition, not once per compound. The build script consumes this to
    # assign curve[[cond]]$conc_key and then drops the raw vector again before
    # writing the detail JSON, so it never duplicates INDEX.concs.
    list(y = unname(d$activity_norm),
         conc = sort(unique(d$conc_m)))
  }
  cond_points <- function(df, cond) {
    d <- df[df$condition == cond, , drop = FALSE]
    d <- d[order(d$conc_m), , drop = FALSE]
    unname(Map(function(a, b) c(a, b), d$conc_m, d$activity_norm))
  }

  list(
    dens = c(grid_spec(lo, hi, GRID_N),
             list(inactive = signif(fx, 4), active = signif(fy, 4))),
    blob = lapply(blob, function(m) signif(unname(m), 4)),
    dens_shift = c(grid_spec(min(sg), max(sg), GRID_N),
                   list(dens = signif(kde_reflected(s, sg), 4))),
    curve = list(
      inactive = c(cond_curve(curves_df, "inactive_preincubation"),
                   list(pts   = cond_points(points_df, "inactive_preincubation"),
                        pEC50 = pec50_band(sx$mean, sx$lo, sx$hi))),
      active   = c(cond_curve(curves_df, "active_preincubation"),
                   list(pts   = cond_points(points_df, "active_preincubation"),
                        pEC50 = pec50_band(sy$mean, sy$lo, sy$hi)))
    )
  )
}

# The DRC y-axis default must be robust to a few runaway curves that would
# otherwise compress the scale. The old app computed this in JS by scanning
# every compound's curve at startup; with per-enzyme lazy loading that data is
# not present then, so compute it once here over the whole dataset instead.
drc_y_bounds <- function(curves_df, points_df) {
  ys <- sort(c(curves_df$activity_norm, points_df$activity_norm))
  ys <- ys[is.finite(ys)]
  q <- function(p) ys[max(1, min(length(ys), round(p * (length(ys) - 1)) + 1))]
  c(min(-1.05, q(0.005) - 0.05), max(0.4, q(0.995) + 0.05))
}

# The concentration series repeats across compounds; hoist the distinct vectors.
shared_concs <- function(curves_df) {
  # pair_id restarts at 1 in every run, so splitting on it alone pools different
  # runs' concentration series into unions that match no real compound. The two
  # conditions of the SAME (run, pair_id) can also differ (22/6894 compounds in
  # the real dataset were fitted over different ranges for inactive vs. active
  # preincubation), so key on condition too — otherwise those pairs pool into a
  # spurious union that matches neither condition's real series.
  per <- split(curves_df$conc_m,
               paste(curves_df$run, curves_df$pair_id, curves_df$condition, sep = "\r"))
  per <- lapply(per, function(v) sort(unique(v)))
  unique(unname(per))
}
