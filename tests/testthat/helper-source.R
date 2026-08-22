# Auto-sourced by testthat before tests. Loads all R/ function files.
# testthat sets wd to tests/testthat during test_dir(), so ../../R is the project R/.
for (f in list.files("../../R", pattern = "\\.R$", full.names = TRUE)) {
  source(f)
}
