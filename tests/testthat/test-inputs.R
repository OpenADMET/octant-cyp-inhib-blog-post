# The guard itself. If require_input() ever goes back to skipping by default,
# these are what notice.

with_env <- function(value, expr) {
  old <- Sys.getenv("CYP_ALLOW_MISSING_INPUTS", unset = NA)
  if (is.na(value)) Sys.unsetenv("CYP_ALLOW_MISSING_INPUTS")
  else Sys.setenv(CYP_ALLOW_MISSING_INPUTS = value)
  on.exit({
    if (is.na(old)) Sys.unsetenv("CYP_ALLOW_MISSING_INPUTS")
    else Sys.setenv(CYP_ALLOW_MISSING_INPUTS = old)
  })
  force(expr)
}

test_that("a present input passes straight through", {
  expect_true(with_env(NA, require_input(TRUE, "build/", "rebuild it")))
})

test_that("a missing input FAILS by default rather than skipping", {
  # This is the whole point: a skip reports success for a test that never ran.
  expect_error(with_env(NA, require_input(FALSE, "build/figure_index.json",
                                          "run scripts/build_figure_data.R")),
               "would not run")
})

test_that("the failure names the missing input and how to get it", {
  e <- tryCatch(with_env(NA, require_input(FALSE, "build/figure_index.json",
                                           "run scripts/build_figure_data.R")),
                error = function(e) conditionMessage(e))
  expect_match(e, "build/figure_index.json", fixed = TRUE)
  expect_match(e, "run scripts/build_figure_data.R", fixed = TRUE)
  expect_match(e, "CYP_ALLOW_MISSING_INPUTS", fixed = TRUE)
})

test_that("CYP_ALLOW_MISSING_INPUTS=1 opts back into skipping", {
  expect_condition(with_env("1", require_input(FALSE, "build/", "rebuild it")),
                   class = "skip")
})

test_that("any other value of the variable does not enable skipping", {
  # Guards against a truthy-looking value silently disarming the guard.
  for (v in c("0", "", "true", "yes")) {
    expect_error(with_env(v, require_input(FALSE, "build/", "rebuild it")),
                 "would not run", info = v)
  }
})
