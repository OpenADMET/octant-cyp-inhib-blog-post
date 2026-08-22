test_that("hdr_level threshold encloses the requested mass", {
  gx <- seq(-5, 5, length.out = 200); gy <- seq(-5, 5, length.out = 200)
  fx <- dnorm(gx); fy <- dnorm(gy)
  f <- outer(fx, fy)
  dx <- mean(diff(gx)); dy <- mean(diff(gy))
  lvl <- hdr_level(f, dx * dy, 0.95)
  enclosed <- sum(f[f >= lvl]) * dx * dy
  expect_equal(enclosed, 0.95, tolerance = 0.02)
})

test_that("joint_blob of two independent normals is a ~circular 95% region", {
  gx <- seq(-5, 5, length.out = 200); gy <- seq(-5, 5, length.out = 200)
  polys <- joint_blob(dnorm(gx), dnorm(gy), gx, gy, 0.95)
  expect_true(length(polys) >= 1)
  p <- polys[[1]]
  # 95% region of iid bivariate normal is the disk radius sqrt(qchisq(.95,2)) ~ 2.448
  r <- sqrt(rowSums(p^2))
  expect_equal(mean(r), sqrt(qchisq(0.95, 2)), tolerance = 0.15)
})

test_that("joint_blob returns a closed-ish polygon with >2 vertices", {
  gx <- seq(0, 6, length.out = 150); gy <- seq(0, 6, length.out = 150)
  fx <- kde_reflected(1 + rexp(4000, 1), gx, lower = 0)
  fy <- kde_reflected(2 + rexp(4000, 1), gy, lower = 0)
  polys <- joint_blob(fx, fy, gx, gy, 0.95)
  expect_gt(nrow(polys[[1]]), 2)
})

test_that("joint_blob keeps inactive on x and active on y (no axis swap)", {
  gx <- seq(0, 8, length.out = 200); gy <- seq(0, 8, length.out = 200)
  fx <- kde_reflected(rnorm(4000, 2, 0.4), gx, lower = 0)   # inactive ~2
  fy <- kde_reflected(rnorm(4000, 6, 0.4), gy, lower = 0)   # active ~6
  polys <- joint_blob(fx, fy, gx, gy, 0.95)
  p <- polys[[1]]
  expect_lt(mean(p[, "x"]), mean(p[, "y"]))   # x(inactive)≈2  <  y(active)≈6
})
