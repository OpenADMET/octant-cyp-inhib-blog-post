# Missing test inputs must FAIL, not skip.
#
# The regression suite reads two artefacts that are not in the repo: build/*.json
# (produced by scripts/build_figure_data.R) and the parquet (staged locally, see
# README). Both used to `skip_if_not`, which reports SUCCESS for a suite that
# tested almost nothing:
#
#   no parquet   ->  4 assertions lost, 1 skip
#   no build/    -> 26 assertions lost, 6 skips   (PASS 99 becomes PASS 73)
#
# Five of the six regression tests need only build/, so the tree most likely to
# look green while checking nothing is one with build/ cleaned — exactly what a
# verify-then-remove cycle leaves behind. Green is the wrong answer there.
#
# Default is therefore a loud failure naming what is absent and how to produce
# it. Set CYP_ALLOW_MISSING_INPUTS=1 to opt back into skipping, for the case
# where someone legitimately has neither — reviewing a diff without a 237 MB
# parquet on hand. It must be exactly "1": a guard that any truthy-looking value
# disarms is not a guard.

require_input <- function(present, what, remedy) {
  if (isTRUE(present)) return(invisible(TRUE))
  if (identical(Sys.getenv("CYP_ALLOW_MISSING_INPUTS"), "1")) {
    testthat::skip(sprintf("%s absent; CYP_ALLOW_MISSING_INPUTS=1", what))
  }
  stop(sprintf(paste0(
    "%s is absent, so this test would not run — and a skipped test reports ",
    "success for something never checked.\n  To fix: %s\n  To skip anyway: ",
    "set CYP_ALLOW_MISSING_INPUTS=1"), what, remedy), call. = FALSE)
}
