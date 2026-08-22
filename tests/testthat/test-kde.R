test_that("reflected kde integrates to ~1 over the domain", {
  set.seed(2); d <- rgamma(4000, 2, 2) + 1        # bounded below at 1
  grid <- seq(1, 6, length.out = 400)
  y <- kde_reflected(d, grid, lower = 1)
  dx <- mean(diff(grid))
  expect_equal(sum(y) * dx, 1, tolerance = 0.02)
})

test_that("reflected kde puts ~no mass below the lower bound", {
  set.seed(3); d <- c(rep(1, 2000), 1 + rexp(2000, 3))  # piled at floor=1
  grid <- seq(0, 5, length.out = 500)
  y <- kde_reflected(d, grid, lower = 1)
  below <- grid < 1
  expect_lt(sum(y[below]), 1e-6)
})

test_that("reflected kde boosts near-boundary density vs naive kde", {
  set.seed(4); d <- 1 + rexp(4000, 2)
  grid <- seq(1, 5, length.out = 400)
  y_refl  <- kde_reflected(d, grid, lower = 1)
  naive <- stats::density(d, from = 1, to = 5, n = 400)
  # at the boundary, reflection should not droop toward zero the way naive does
  expect_gt(y_refl[1], naive$y[1])
})
