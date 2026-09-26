# Checks whether the package's test support files (test_support_files():
# setup*.R and helper*.R — not only setup.R) already wire up a DSLite
# server (via DSFunctionCreator's init.dsTest() or hand-written). If this
# is TRUE, no dataset is ever suggested and no setup.R is generated —
# generated tests use the existing setup, which Claude sees verbatim.
detect_dslite_setup <- function() {
  any(vapply(test_support_files(), function(path) {
    content <- paste(readLines(path, warn = FALSE), collapse = "\n")
    grepl("DSLite", content, fixed = TRUE) || grepl("datashield\\.login", content)
  }, logical(1)))
}
