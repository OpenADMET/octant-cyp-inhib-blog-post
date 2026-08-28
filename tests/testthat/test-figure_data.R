source("../../R/stats_shift.R")
source("../../R/figure_data.R")

# Two compounds in one run: one with a large positive shift, one with none.
make_fixture <- function() {
  dir <- tempfile(); dir.create(dir)
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  set.seed(1)
  mk <- function(pair, cond, mu) data.frame(
    pair_id = pair, compound_id = paste0("CPD-", pair), condition = cond,
    chain = rep(1:4, each = 250), iteration = rep(1:250, times = 4),
    draw = 1:1000, pEC50 = rnorm(1000, mu, 0.05),
    SlopeLog2 = rnorm(1000, 0.1, 0.02))
  draws <- rbind(
    mk(1, "inactive_preincubation", 5.0), mk(1, "active_preincubation", 6.0),
    mk(2, "inactive_preincubation", 5.0), mk(2, "active_preincubation", 5.0))
  compounds <- data.frame(
    pair_id = 1:2, enzyme = "CYP3A4", run = "CYP3A4-3",
    compound_id = c("CPD-1", "CPD-2"), molecule_name = NA_character_,
    batch_name = NA_character_, plate = "Plate01",
    compound_name = NA_character_, compound_deck = NA_character_,
    compound_class = c("Library", "Library"),
    # Deliberately does not match what the raw compound_class would recode to
    # (that would be "Unknown") -- see the test below for why.
    tdi_annotation = c("TDI (control)", "TDI (control)"),
    cxsmiles = "CCO", standardized_smiles = "CCO")

  dp <- file.path(dir, "draws", "enzyme=CYP3A4", "run=CYP3A4-3")
  cp <- file.path(dir, "compounds", "run=CYP3A4-3")
  dir.create(dp, recursive = TRUE); dir.create(cp, recursive = TRUE)
  duckdb::duckdb_register(con, "d", draws)
  duckdb::duckdb_register(con, "c", compounds)
  DBI::dbExecute(con, sprintf("COPY (SELECT * FROM d) TO '%s' (FORMAT PARQUET)",
                              file.path(dp, "part-0.parquet")))
  DBI::dbExecute(con, sprintf("COPY (SELECT * FROM c) TO '%s' (FORMAT PARQUET)",
                              file.path(cp, "part-0.parquet")))
  dir
}

test_that("compound_summary returns one row per pair with both conditions", {
  d <- make_fixture()
  con <- open_data(d); on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  s <- compound_summary(con, d)
  expect_equal(nrow(s), 2L)
  expect_setequal(s$compound_id, c("CPD-1", "CPD-2"))
  expect_equal(s$enzyme, c("CYP3A4", "CYP3A4"))
})

test_that("compound_summary exposes tdi_annotation as the compound_class field", {
  # tdi_annotation is the semantic TDI label, computed once upstream in the
  # export pipeline and published as its own parquet column -- one source of
  # truth for the mapping. compound_summary() must expose it under the
  # compound_class name (what the index JSON and JS already key on) without
  # recomputing anything from the raw assay compound_class. The fixture's
  # tdi_annotation ("TDI (control)") deliberately differs from what the raw
  # compound_class ("Library") would have recoded to under the old in-repo
  # mapping ("Unknown"), so this fails if compound_summary starts deriving
  # compound_class again instead of reading tdi_annotation straight through.
  d <- make_fixture()
  con <- open_data(d); on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  s <- compound_summary(con, d)
  expect_true(all(s$compound_class == "TDI (control)"))
})

test_that("the shift is active minus inactive", {
  d <- make_fixture()
  con <- open_data(d); on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  s <- compound_summary(con, d)
  expect_equal(s$shift_mean[s$compound_id == "CPD-1"], 1.0, tolerance = 0.02)
  expect_equal(s$shift_mean[s$compound_id == "CPD-2"], 0.0, tolerance = 0.02)
})

test_that("the summary carries what every hit-calling mode needs, and no verdict", {
  d <- make_fixture()
  con <- open_data(d); on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  s <- compound_summary(con, d)
  # The figure decides significance at runtime from adjustable thresholds, so
  # these inputs must be present and no precomputed flag may be.
  for (col in c("shift_mean", "shift_lo", "shift_hi",
                "active_mean", "active_lo", "active_hi",
                "inactive_lo", "inactive_hi")) {
    expect_true(col %in% names(s), info = col)
  }
  expect_false(any(grepl("^sig", names(s))))
})

test_that("credible interval bounds bracket the mean", {
  d <- make_fixture()
  con <- open_data(d); on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  s <- compound_summary(con, d)
  expect_true(all(s$inactive_lo < s$inactive_mean & s$inactive_mean < s$inactive_hi))
  expect_true(all(s$shift_lo < s$shift_mean & s$shift_mean < s$shift_hi))
})

test_that("compound_detail returns densities on a compact grid spec", {
  set.seed(2)
  dr <- data.frame(
    condition = rep(c("inactive_preincubation", "active_preincubation"), each = 1000),
    chain = rep(rep(1:4, each = 250), 2), iteration = rep(rep(1:250, 4), 2),
    pEC50 = c(rnorm(1000, 5, 0.1), rnorm(1000, 6, 0.1)))
  cv <- data.frame(condition = rep(c("inactive_preincubation", "active_preincubation"), each = 3),
                   conc_m = rep(c(1e-9, 1e-8, 1e-7), 2),
                   activity_norm = c(1, .9, .8, 1, .6, .3),
                   fc_vs_dmso = c(2, 1.8, 1.6, 2, 1.2, .6))
  pt <- cv
  d <- compound_detail(dr, cv, pt)

  expect_named(d$dens, c("lo", "hi", "n", "inactive", "active"))
  expect_length(d$dens$inactive, d$dens$n)
  expect_length(d$dens$active,   d$dens$n)
  expect_true(d$dens$lo < d$dens$hi)
  expect_named(d$dens_shift, c("lo", "hi", "n", "dens"))
  expect_length(d$dens_shift$dens, d$dens_shift$n)
})

test_that("the joint blob is a non-empty set of closed polygons", {
  set.seed(3)
  dr <- data.frame(
    condition = rep(c("inactive_preincubation", "active_preincubation"), each = 1000),
    chain = rep(rep(1:4, each = 250), 2), iteration = rep(rep(1:250, 4), 2),
    pEC50 = c(rnorm(1000, 5, 0.1), rnorm(1000, 6, 0.1)))
  cv <- data.frame(condition = rep(c("inactive_preincubation", "active_preincubation"), each = 3),
                   conc_m = rep(c(1e-9, 1e-8, 1e-7), 2),
                   activity_norm = c(1, .9, .8, 1, .6, .3),
                   fc_vs_dmso = c(2, 1.8, 1.6, 2, 1.2, .6))
  d <- compound_detail(dr, cv, cv)
  expect_gt(length(d$blob), 0)
  expect_equal(ncol(d$blob[[1]]), 2L)
  expect_gt(nrow(d$blob[[1]]), 3L)
})

test_that("the blob sits where the two marginals are, not somewhere else", {
  set.seed(4)
  dr <- data.frame(
    condition = rep(c("inactive_preincubation", "active_preincubation"), each = 1000),
    chain = rep(rep(1:4, each = 250), 2), iteration = rep(rep(1:250, 4), 2),
    pEC50 = c(rnorm(1000, 5, 0.1), rnorm(1000, 6, 0.1)))
  cv <- data.frame(condition = rep(c("inactive_preincubation", "active_preincubation"), each = 3),
                   conc_m = rep(c(1e-9, 1e-8, 1e-7), 2),
                   activity_norm = c(1, .9, .8, 1, .6, .3),
                   fc_vs_dmso = c(2, 1.8, 1.6, 2, 1.2, .6))
  d <- compound_detail(dr, cv, cv)
  xy <- do.call(rbind, d$blob)
  # x is the inactive condition (mean 5), y the active (mean 6).
  expect_true(mean(xy[, 1]) > 4.5 && mean(xy[, 1]) < 5.5)
  expect_true(mean(xy[, 2]) > 5.5 && mean(xy[, 2]) < 6.5)
})

test_that("curves keep both conditions and expose each one's own concentrations", {
  set.seed(5)
  dr <- data.frame(
    condition = rep(c("inactive_preincubation", "active_preincubation"), each = 1000),
    chain = rep(rep(1:4, each = 250), 2), iteration = rep(rep(1:250, 4), 2),
    pEC50 = c(rnorm(1000, 5, 0.1), rnorm(1000, 6, 0.1)))
  cv <- data.frame(condition = rep(c("inactive_preincubation", "active_preincubation"), each = 3),
                   conc_m = rep(c(1e-9, 1e-8, 1e-7), 2),
                   activity_norm = c(1, .9, .8, 1, .6, .3),
                   fc_vs_dmso = c(2, 1.8, 1.6, 2, 1.2, .6))
  d <- compound_detail(dr, cv, cv)
  expect_equal(d$curve$inactive$y, c(1, .9, .8))
  expect_equal(d$curve$active$y,   c(1, .6, .3))
  # conc_key is looked up per condition (build script), not per compound, since
  # the two conditions can be fitted over different ranges — cond_curve() must
  # expose its own condition's concentrations for that lookup to work at all.
  # (The build script deletes this raw vector again before writing the detail
  # JSON, once it has resolved conc_key from it — that happens outside this
  # function, so it is not asserted here.)
  expect_equal(d$curve$inactive$conc, c(1e-9, 1e-8, 1e-7))
  expect_equal(d$curve$active$conc,   c(1e-9, 1e-8, 1e-7))
})

test_that("the pEC50 band is in concentration units and ascending", {
  # A pEC50 of 6 is 1e-6 M, and a HIGHER pEC50 is a LOWER concentration, so the
  # interval flips: band[1] comes from hi, band[2] from lo.
  b <- pec50_band(6, 5.5, 6.5)
  expect_equal(b$line, 1e-6)
  expect_equal(b$band, c(10^-6.5, 10^-5.5))
  expect_lt(b$band[1], b$band[2])
  expect_true(b$band[1] < b$line && b$line < b$band[2])
})

test_that("compound_detail attaches a pEC50 band to each condition", {
  set.seed(6)
  dr <- data.frame(
    condition = rep(c("inactive_preincubation", "active_preincubation"), each = 1000),
    chain = rep(rep(1:4, each = 250), 2), iteration = rep(rep(1:250, 4), 2),
    pEC50 = c(rnorm(1000, 5, 0.1), rnorm(1000, 6, 0.1)))
  cv <- data.frame(condition = rep(c("inactive_preincubation", "active_preincubation"), each = 3),
                   conc_m = rep(c(1e-9, 1e-8, 1e-7), 2),
                   activity_norm = c(1, .9, .8, 1, .6, .3),
                   fc_vs_dmso = c(2, 1.8, 1.6, 2, 1.2, .6))
  d <- compound_detail(dr, cv, cv)
  # active has the higher pEC50 (6 vs 5), so its line sits at a LOWER concentration
  expect_lt(d$curve$active$pEC50$line, d$curve$inactive$pEC50$line)
  expect_length(d$curve$inactive$pEC50$band, 2L)
})

test_that("drc_y_bounds anchors near the activity floor and ignores a runaway curve", {
  cv <- data.frame(activity_norm = c(rep(c(-1, 0, 0.5), 200), 500))  # one runaway
  pt <- data.frame(activity_norm = rep(c(-1, 0, 0.4), 200))
  b <- drc_y_bounds(cv, pt)
  expect_lte(b[1], -1.05)
  expect_lt(b[2], 10)            # the 500 must not set the top
  expect_gte(b[2], 0.4)
  # Coverage gap closer: a stub that ignores its arguments and always returns
  # the literal floor/ceiling defaults c(-1.05, 0.4) would pass every check
  # above. The real upper quantile here sits at 0.5 (the 0.5-mass cluster,
  # not the runaway 500), so it must clear 0.4, not just tie it.
  expect_gt(b[2], 0.4)
})

test_that("shared_concs deduplicates the concentration vectors", {
  # run and condition held constant: this test isolates dedup-by-value alone.
  cv <- data.frame(
    run = "R1", condition = "inactive_preincubation",
    pair_id = rep(1:3, each = 3),
    conc_m = c(1e-9, 1e-8, 1e-7,  1e-9, 1e-8, 1e-7,  1e-9, 1e-8, 1e-6))
  sc <- shared_concs(cv)
  expect_equal(length(sc), 2L)
  # Coverage gap closer: a stub that ignores curves_df and always returns some
  # fixed 2-element list would also pass the length check above. Pin the
  # actual distinct concentration vectors so the result must come from the data.
  expect_true(any(vapply(sc, identical, logical(1), c(1e-9, 1e-8, 1e-7))))
  expect_true(any(vapply(sc, identical, logical(1), c(1e-9, 1e-8, 1e-6))))
})

test_that("shared_concs keys on (run, pair_id, condition), not pair_id alone", {
  # pair_id 1 exists in both runs with DIFFERENT concentration series. Splitting
  # on pair_id alone pools them into one spurious union and finds fewer vectors.
  # condition is held constant here to isolate this from the condition-splitting
  # behavior, which is tested separately below.
  cv <- data.frame(
    run     = c(rep("R1", 3), rep("R2", 3)),
    condition = "inactive_preincubation",
    pair_id = c(1, 1, 1, 1, 1, 1),
    conc_m  = c(1e-9, 1e-8, 1e-7,  1e-6, 1e-5, 1e-4))
  sc <- shared_concs(cv)
  expect_length(sc, 2L)
  expect_true(any(vapply(sc, function(v) isTRUE(all.equal(v, c(1e-9, 1e-8, 1e-7))), logical(1))))
  expect_true(any(vapply(sc, function(v) isTRUE(all.equal(v, c(1e-6, 1e-5, 1e-4))), logical(1))))
})

test_that("shared_concs splits by condition too: mismatched per-condition ranges don't pool", {
  # The bug this guards against: the same (run, pair_id) compound whose two
  # preincubation conditions were fitted over DIFFERENT concentration ranges
  # (22/6894 in the real dataset). Keying on (run, pair_id) alone pools both
  # conditions' conc_m into one spurious union that matches neither condition's
  # real series — which is exactly how a 250-point y-vector ends up plotted
  # against a 499-point x-vector. Keying on condition too must yield the two
  # real per-condition series, not one union.
  cv <- data.frame(
    run = "R1", pair_id = 1,
    condition = c(rep("inactive_preincubation", 3), rep("active_preincubation", 4)),
    conc_m = c(1e-9, 2e-9, 3e-9, 4e-9, 5e-9, 6e-9, 7e-9))
  sc <- shared_concs(cv)
  expect_length(sc, 2L)
  expect_true(any(vapply(sc, function(v) isTRUE(all.equal(v, c(1e-9, 2e-9, 3e-9))), logical(1))))
  expect_true(any(vapply(sc, function(v) isTRUE(all.equal(v, c(4e-9, 5e-9, 6e-9, 7e-9))), logical(1))))
  # The spurious union (what the pre-fix (run,pair_id)-only key would have
  # produced) must NOT appear as a single pooled vector — it has neither
  # condition's real length (3 or 4) nor real values (it's all 7 pooled).
  union_wrong <- sort(unique(cv$conc_m))
  expect_false(any(vapply(sc, function(v) isTRUE(all.equal(v, union_wrong)), logical(1))))
})
