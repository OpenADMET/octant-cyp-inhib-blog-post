# Declares packages renv's static analysis cannot see, so `renv::snapshot()`
# keeps finding them. Not sourced by anything -- it exists only to be scanned.
#
# testthat: the suite calls bare test_that() with no library(testthat) or
# testthat:: anywhere, and is invoked from the command line as
#   Rscript -e 'testthat::test_dir("tests/testthat")'
# so nothing in the repo's R sources references it. Without this line it drops
# out of the lockfile and a restored project cannot run its own documented
# test command.
library(testthat)
