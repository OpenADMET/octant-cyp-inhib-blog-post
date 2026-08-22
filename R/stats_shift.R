LOG2_2 <- log10(2)

# Posterior summary with brms defaults: mean + central 95% (type-7 quantiles).
summ <- function(draws) {
  list(
    mean = mean(draws),
    lo   = unname(posterior::quantile2(draws, 0.025)),
    hi   = unname(posterior::quantile2(draws, 0.975))
  )
}

# Shift = active - inactive, elementwise over independent draws.
compute_shift <- function(x, y) {
  s <- y - x
  c(summ(s), list(draws = s))
}

# Significant positive TDI shift: point estimate clears the 2x (log10(2))
# threshold AND the 95% credible interval excludes zero.
is_significant <- function(shift_mean, shift_lo, log2_2 = LOG2_2) {
  isTRUE(shift_mean > log2_2 && shift_lo > 0)
}

# Thin a polygon/curve to at most `target` points, keeping the endpoints.
downsample_idx <- function(n, target) {
  if (n <= target) return(seq_len(n))
  unique(round(seq(1, n, length.out = target)))
}

# Polygon area (shoelace). Used to drop negligible HDR contour specks so a
# genuinely multimodal blob reads cleanly — keeps the real modes, drops the
# sub-percent fragments that are KDE grid noise.
poly_area <- function(m) {
  n <- nrow(m); if (n < 3) return(0)
  x <- m[, 1]; y <- m[, 2]
  abs(sum(x * y[c(2:n, 1)] - x[c(2:n, 1)] * y)) / 2
}

drop_specks <- function(polys, frac = 0.02) {
  if (length(polys) <= 1) return(polys)
  a <- vapply(polys, poly_area, numeric(1))
  keep <- a >= max(a) * frac
  if (!any(keep)) keep[which.max(a)] <- TRUE
  polys[keep]
}
