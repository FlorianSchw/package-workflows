# Lazily creates tests/testthat/setup.R once per package when a client-side
# function needs DSLite and no existing setup.R was found by
# detect_dslite_setup(). Safe to call once per processed function — only
# writes on the first call that actually needs it, since a second call
# would find the file already exists.
ensure_dslite_setup_file <- function(dataset_choice, package_name) {
  path <- file.path("tests", "testthat", "setup.R")
  if (file.exists(path)) return(invisible(NULL))

  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  snippet <- build_dslite_test_snippet(dataset_choice, package_name)
  writeLines(snippet, path)
  invisible(path)
}
