test_that("summ returns brms-default mean and 95% quantiles", {
  set.seed(1); d <- rnorm(4000, mean = 2, sd = 0.5)
  s <- summ(d)
  expect_equal(s$mean, mean(d))
  expect_equal(unname(s$lo), unname(posterior::quantile2(d, 0.025)))
  expect_equal(unname(s$hi), unname(posterior::quantile2(d, 0.975)))
})

test_that("compute_shift subtracts elementwise (active - inactive)", {
  x <- c(1, 2, 3, 4); y <- c(2, 4, 6, 8)     # inactive, active
  r <- compute_shift(x, y)
  expect_equal(r$draws, c(1, 2, 3, 4))
  expect_equal(r$mean, 2.5)
})

test_that("is_significant needs both a >log10(2) mean AND CI excluding zero", {
  expect_true(is_significant(0.9, 0.4))     # clears both
  expect_false(is_significant(0.9, -0.1))   # CI overlaps zero
  expect_false(is_significant(0.2, 0.05))   # mean below log10(2)
  expect_false(is_significant(log10(2), 0.1)) # strictly greater, boundary excluded
})

test_that("drop_specks keeps real modes and drops sub-threshold fragments", {
  big   <- cbind(c(0, 2, 2, 0), c(0, 0, 2, 2))      # area 4
  small <- cbind(c(0, 0.1, 0.1, 0), c(0, 0, 0.1, 0)) # area 0.005, well under 2% of 4
  expect_length(drop_specks(list(big, small)), 1L)
  expect_equal(drop_specks(list(big, small))[[1]], big)
})

test_that("drop_specks keeps two comparable modes", {
  a <- cbind(c(0, 2, 2, 0), c(0, 0, 2, 2))
  b <- cbind(c(5, 7, 7, 5), c(0, 0, 2, 2))
  expect_length(drop_specks(list(a, b)), 2L)
})

test_that("drop_specks never returns nothing", {
  tiny <- cbind(c(0, 0.01, 0.01, 0), c(0, 0, 0.01, 0))
  expect_length(drop_specks(list(tiny)), 1L)
})
