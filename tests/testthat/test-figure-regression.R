# The index JSON is what the figure actually plots. Check it against the parquet
# it was built from, so a bug in the build script cannot pass unnoticed.
BUILD <- "../../build"
IDX <- file.path(BUILD, "figure_index.json")
DATA <- Sys.getenv("CYP_DATA_DIR", unset = "../../scratch/data")

test_that("the index reproduces the parquet's pEC50 summaries", {
  skip_if_not(file.exists(IDX), "run scripts/build_figure_data.R first")
  skip_if_not(dir.exists(DATA), "parquet not available")
  source("../../R/stats_shift.R"); source("../../R/figure_data.R")

  j <- jsonlite::fromJSON(IDX, simplifyDataFrame = TRUE)
  fig <- data.frame(run = j$compounds$run, pair_id = j$compounds$pair_id,
                    inactive = j$compounds$inactive$pEC50,
                    active = j$compounds$active$pEC50,
                    shift = j$compounds$shift$mean,
                    stringsAsFactors = FALSE)

  con <- open_data(DATA); on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  s <- compound_summary(con, normalizePath(DATA))

  m <- merge(fig, s, by = c("run", "pair_id"))
  expect_equal(nrow(m), nrow(fig))
  expect_equal(m$inactive, m$inactive_mean, tolerance = 1e-3)
  expect_equal(m$active,   m$active_mean,   tolerance = 1e-3)
  expect_equal(m$shift,    m$shift_mean,    tolerance = 1e-3)
})

test_that("every compound in the index has a detail entry", {
  skip_if_not(file.exists(IDX), "run scripts/build_figure_data.R first")
  j <- jsonlite::fromJSON(IDX, simplifyDataFrame = TRUE)
  for (e in j$meta$enzymes) {
    p <- sprintf("../../build/figure_detail_%s.json", e)
    skip_if_not(file.exists(p), paste("no detail for", e))
    d <- jsonlite::fromJSON(p, simplifyVector = FALSE)
    want <- with(j$compounds[j$compounds$enzyme == e, ], paste0(run, ":", pair_id))
    expect_length(setdiff(want, names(d)), 0)
  }
})

test_that("every compound's per-condition conc_key resolves to a same-length vector", {
  # conc_key lives per condition inside each detail entry's curve object, not
  # on the compound as a whole (Task 5): 22/6,894 compounds were fitted over
  # different concentration ranges for their two preincubation conditions, so
  # a compound-level key can point one condition's y-values at the wrong
  # x-vector — silently, since both are plain numeric vectors of some length.
  # The length check below is what would have caught that: a wrong-but-valid
  # index (in range, integer) can still point at a vector of the wrong length.
  skip_if_not(file.exists(IDX), "run scripts/build_figure_data.R first")
  j <- jsonlite::fromJSON(IDX, simplifyDataFrame = TRUE)

  # simplifyVector's default folds a list of same-length numeric vectors into
  # a matrix, which would silently swap "how many concentration vectors" for
  # "how many numbers total" -- read concs with simplification off instead.
  concs <- jsonlite::fromJSON(IDX, simplifyVector = FALSE)$concs
  conc_len <- lengths(concs)

  # A key that is missing or JSON null has no length-1 numeric value, so vapply
  # itself is the not-null check.
  key <- numeric(0); y_len <- integer(0)
  for (e in j$meta$enzymes) {
    p <- sprintf("../../build/figure_detail_%s.json", e)
    skip_if_not(file.exists(p), paste("no detail for", e))
    d <- jsonlite::fromJSON(p, simplifyVector = FALSE)

    for (cond in c("inactive", "active")) {
      key <- c(key, vapply(d, function(cd) as.numeric(cd$curve[[cond]]$conc_key),
                           numeric(1), USE.NAMES = FALSE))
      y_len <- c(y_len, vapply(d, function(cd) length(cd$curve[[cond]]$y),
                               integer(1), USE.NAMES = FALSE))
    }
  }
  # 6,894 compounds x 2 conditions.
  expect_length(key, 13788L)
  expect_false(anyNA(key))
  expect_true(all(key == round(key) & key >= 1 & key <= length(concs)))
  expect_equal(unname(conc_len[key]), y_len)
})

test_that("compound names cover exactly the expected population", {
  skip_if_not(file.exists(IDX), "run scripts/build_figure_data.R first")
  idx <- jsonlite::fromJSON(file.path(BUILD, "figure_index.json"),
                            simplifyDataFrame = FALSE)
  cmp <- idx$compounds
  nm <- vapply(cmp, function(x) if (is.null(x$compound_name)) NA_character_
                                else x$compound_name, character(1))
  ids <- vapply(cmp, function(x) x$compound_id, character(1))
  cls <- vapply(cmp, function(x) x$compound_class, character(1))

  expect_equal(sum(!is.na(nm)), 794L)
  expect_equal(length(unique(ids[!is.na(nm)])), 316L)
  expect_false(any(nm[!is.na(nm)] == "NA"))          # the jsonlite trap
  expect_true(all(!is.na(nm[cls != "Unknown"])))     # all 370 annotated rows named
  expect_equal(unique(nm[ids == "OCNT-1911798-AQ-002"]), "Fluoxetine")
})

test_that("each named compound carries the right name, not merely a name", {
  # The counts above are all satisfied by a permutation: shuffling
  # compound_name across the named rows leaves 794 named, 316 distinct, every
  # annotated row named and fluoxetine pinned, while propranolol renders as
  # "Flufenamic acid". Demonstrated on a mutated copy of the index: pinning
  # fluoxetine and shuffling the rest left the overwhelming majority of named
  # rows wrong with all five assertions still green. This test is what fails
  # on that index. (The original demonstration was 748 of 796 rows, run
  # against the pre-exclusion build; the point does not depend on the exact
  # tally, so it is not restated as a number that has to be maintained.)
  skip_if_not(file.exists(IDX), "run scripts/build_figure_data.R first")
  idx <- jsonlite::fromJSON(file.path(BUILD, "figure_index.json"),
                            simplifyDataFrame = FALSE)
  cmp <- idx$compounds
  nm <- vapply(cmp, function(x) if (is.null(x$compound_name)) NA_character_
                                else x$compound_name, character(1))
  ids <- vapply(cmp, function(x) x$compound_id, character(1))

  # One pair per named compound: 316 unique pairs from 794 rows is itself the
  # assertion that a compound never carries two different names across runs.
  # Counted on compound_id, not molecule: the 316 distinct named compound_ids
  # cover 315 distinct molecules, one of them registered under two batches.
  pairs <- sort(unique(paste(ids[!is.na(nm)], nm[!is.na(nm)], sep = "\t")))
  expect_equal(length(pairs), 316L)
  # serialize = FALSE hashes the bytes rather than an R serialisation header,
  # so the digest does not move with the R version.
  expect_equal(digest::digest(paste(pairs, collapse = "\n"),
                              algo = "sha256", serialize = FALSE),
               "c1af0bc0dab892c9c16365c2009b77b36426ee560bc731cd0418cc8a71ba9dad")

  # The digest says "something changed"; these say what it should have been.
  # The two typo corrections, and vendor names that ship as-is -- the salt
  # forms are here because an earlier version of the export stripped
  # counterions, and that is the regression this map exists to name.
  spot <- c(
    "OCNT-2328870-JG-001" = "Azatadine dimaleate",  # vendor typo "Azatadine dimaleat", corrected
    "OCNT-2328791-AQ-001" = "Benzethonium chloride",# vendor typo "Benzethonium cloride", corrected
    "OCNT-2328368-AQ-001" = "Phenoxybenzamine HCl", # vendor spelling, shipped as-is
    "OCNT-2328370-AQ-001" = "Pramocaine hydrochloride",
    "OCNT-2328485-AQ-001" = "Antazoline hydrochloride"
  )
  for (id in names(spot)) {
    expect_equal(unique(nm[ids == id]), unname(spot[id]), info = id)
  }
})

test_that("deck annotation covers the library", {
  skip_if_not(file.exists(IDX), "run scripts/build_figure_data.R first")
  idx <- jsonlite::fromJSON(file.path(BUILD, "figure_index.json"),
                            simplifyDataFrame = FALSE)
  cmp <- idx$compounds
  dk <- vapply(cmp, function(x) if (is.null(x$compound_deck)) NA_character_
                                else x$compound_deck, character(1))

  expect_equal(sum(!is.na(dk)), 5961L)
  expect_setequal(unique(dk[!is.na(dk)]),
                  c("Enamine FDA-Approved", "Enamine Discovery Diversity"))
})
