# Gaussian KDE with reflection across finite bounds, evaluated on `grid`.
# Reflection avoids the boundary bias / mass leakage of a naive KDE when the
# posterior piles against a hard bound (e.g. pEC50 prior floor = 1).
kde_reflected <- function(draws, grid, lower = -Inf, upper = Inf, bw = NULL) {
  draws <- draws[is.finite(draws)]
  if (length(draws) < 2) {
    y <- numeric(length(grid))
    j <- which.min(abs(grid - (if (length(draws)) draws[1] else mean(grid))))
    y[j] <- 1 / mean(diff(grid)); return(y)
  }
  if (is.null(bw)) bw <- stats::bw.nrd0(draws)
  bw <- max(bw, 1e-3)

  augmented <- draws
  if (is.finite(lower)) augmented <- c(augmented, 2 * lower - draws)
  if (is.finite(upper)) augmented <- c(augmented, 2 * upper - draws)

  dens <- stats::density(augmented, bw = bw,
                         from = min(grid) - 3 * bw, to = max(grid) + 3 * bw, n = 1024)
  y <- stats::approx(dens$x, dens$y, xout = grid, rule = 2)$y
  y[grid < lower | grid > upper] <- 0

  dx <- mean(diff(grid))
  area <- sum(y) * dx
  if (area > 0) y <- y / area
  y
}
