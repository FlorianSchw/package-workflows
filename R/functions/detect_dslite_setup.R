# Checks whether tests/testthat/setup.R already exists and already wires up
# a DSLite server (via DSFunctionCreator's init.dsTest() or hand-written).
# Priority #1 in the dataset-selection order: if this is TRUE, no dataset is
# ever suggested — generated tests are written to assume this existing setup.
detect_dslite_setup <- function() {
  path <- file.path("tests", "testthat", "setup.R")
  if (!file.exists(path)) return(FALSE)
  content <- paste(readLines(path, warn = FALSE), collapse = "\n")
  grepl("DSLite", content, fixed = TRUE) || grepl("datashield\\.login", content)
}
