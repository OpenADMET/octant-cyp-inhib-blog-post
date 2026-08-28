#!/usr/bin/env Rscript
# parquet -> build/figure_index.json + build/figure_detail_<ENZYME>.json
#
# Serial by design: duckdb does the summaries in ~2 s and R does all 6,894
# compounds' KDEs and contours in ~1.4 min. Parallelism is not warranted.

suppressPackageStartupMessages({library(jsonlite)})
HERE <- dirname(dirname(normalizePath(sub("^--file=", "",
  grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))))
for (f in c("kde.R", "blob.R", "stats_shift.R", "figure_data.R")) {
  source(file.path(HERE, "R", f))
}

getarg <- function(flag, default) {
  a <- commandArgs(TRUE); i <- which(a == flag); if (length(i)) a[i + 1] else default
}
data_dir <- path.expand(getarg("--data", file.path(HERE, "scratch/data")))
out_dir  <- getarg("--out", file.path(HERE, "build"))
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

con <- open_data(data_dir)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

message("summaries ...")
S <- compound_summary(con, data_dir)
message("  ", nrow(S), " compounds")

message("hoisting concentration vectors ...")
all_curves <- curves_tbl(con, data_dir) %>%
  select(run, pair_id, condition, conc_m, activity_norm) %>% collect()
all_points <- points_tbl(con, data_dir) %>%
  select(run, pair_id, condition, conc_m, activity_norm) %>% collect()

concs <- shared_concs(all_curves)
conc_of <- function(v) {
  for (i in seq_along(concs)) if (isTRUE(all.equal(concs[[i]], v))) return(i)
  NA_integer_
}

message("details ...")
detail <- list(); key <- paste0(S$run, ":", S$pair_id)

for (enz in sort(unique(S$enzyme))) {
  idx <- which(S$enzyme == enz)
  dd <- draws_tbl(con, data_dir) %>%
    filter(enzyme == !!enz) %>%
    select(run, pair_id, condition, chain, iteration, pEC50) %>% collect()
  dsplit <- split(dd, paste0(dd$run, ":", dd$pair_id))
  csplit <- split(all_curves, paste0(all_curves$run, ":", all_curves$pair_id))
  psplit <- split(all_points, paste0(all_points$run, ":", all_points$pair_id))

  out <- list()
  for (i in idx) {
    k <- key[i]
    cv <- csplit[[k]]; pt <- psplit[[k]]
    if (is.null(cv) || is.null(pt) || is.null(dsplit[[k]])) next
    cd <- compound_detail(dsplit[[k]], cv, pt)
    # conc_key belongs to the condition, not the compound: the two
    # preincubation conditions can be fitted over different concentration
    # ranges for the same compound, so a single compound-level key can
    # silently pair one condition's y-values against the other condition's
    # x-values. Look the key up per condition, then drop the raw vector again
    # so the detail JSON doesn't duplicate INDEX.concs.
    for (cond in c("inactive", "active")) {
      cd$curve[[cond]]$conc_key <- conc_of(cd$curve[[cond]]$conc)
      cd$curve[[cond]]$conc <- NULL
    }
    out[[k]] <- cd
  }
  p <- file.path(out_dir, sprintf("figure_detail_%s.json", enz))
  write_json(out, p, auto_unbox = TRUE, digits = I(4), null = "null")
  message("  ", enz, ": ", length(out), " -> ", basename(p),
          sprintf(" (%.1f MB)", file.size(p) / 1e6))
}

message("index ...")
# jsonlite writes NA_character_ as the STRING "NA", not null, and this script
# passes null = "null" -- so an NA name would render as a literal "NA" in the
# detail panel. Emit NULL instead.
nz <- function(x) if (is.na(x)) NULL else x

idx_obj <- list(
  meta = list(enzymes = sort(unique(S$enzyme)), runs = sort(unique(S$run)),
              log2_2 = LOG2_2,
              # Computed here, not in JS: the old app derived these by scanning
              # every compound's curve at startup, which lazy detail loading
              # makes impossible.
              drc_y = drc_y_bounds(all_curves, all_points),
              # Run labels grouped by enzyme, so the run filter can be per-facet.
              runs_by_enzyme = lapply(split(S$run, S$enzyme), function(v) sort(unique(v)))),
  concs = lapply(concs, function(v) signif(v, 6)),
  compounds = lapply(seq_len(nrow(S)), function(i) list(
    enzyme = S$enzyme[i], run = S$run[i], pair_id = S$pair_id[i],
    compound_id = S$compound_id[i], compound_class = S$compound_class[i],
    compound_name = nz(S$compound_name[i]), compound_deck = nz(S$compound_deck[i]),
    plate = S$plate[i], smiles = S$smiles[i],
    inactive = list(pEC50 = signif(S$inactive_mean[i], 4), lo = signif(S$inactive_lo[i], 4),
                    hi = signif(S$inactive_hi[i], 4),
                    slope = list(mean = signif(S$slope_inactive[i], 4),
                                 lo   = signif(S$slope_inactive_lo[i], 4),
                                 hi   = signif(S$slope_inactive_hi[i], 4))),
    active   = list(pEC50 = signif(S$active_mean[i], 4), lo = signif(S$active_lo[i], 4),
                    hi = signif(S$active_hi[i], 4),
                    slope = list(mean = signif(S$slope_active[i], 4),
                                 lo   = signif(S$slope_active_lo[i], 4),
                                 hi   = signif(S$slope_active_hi[i], 4))),
    shift = list(mean = signif(S$shift_mean[i], 4), lo = signif(S$shift_lo[i], 4),
                 hi = signif(S$shift_hi[i], 4))
  ))
)
p <- file.path(out_dir, "figure_index.json")
write_json(idx_obj, p, auto_unbox = TRUE, digits = I(4), null = "null")
message("  ", nrow(S), " -> ", basename(p), sprintf(" (%.1f MB)", file.size(p) / 1e6))
