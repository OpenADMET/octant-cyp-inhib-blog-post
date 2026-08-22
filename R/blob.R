# Hyndman (1996) density-quantile rule: the level whose super-level set holds `mass`.
hdr_level <- function(f, cell_area, mass = 0.95) {
  fs <- sort(as.vector(f), decreasing = TRUE)
  cum <- cumsum(fs) * cell_area
  total <- cum[length(cum)]
  idx <- which(cum >= mass * total)[1]
  if (is.na(idx)) idx <- length(fs)
  fs[idx]
}

# 95% joint highest-density region as contour polygon(s).
# Independence => joint density is the outer product of the marginal KDEs.
joint_blob <- function(fx, fy, gx, gy, mass = 0.95) {
  f  <- outer(fx, fy)                      # f[i, j] ~ (gx[i], gy[j])
  dx <- mean(diff(gx)); dy <- mean(diff(gy))
  lvl <- hdr_level(f, dx * dy, mass)
  cl <- grDevices::contourLines(gx, gy, f, levels = lvl)
  lapply(cl, function(p) cbind(x = p$x, y = p$y))
}
