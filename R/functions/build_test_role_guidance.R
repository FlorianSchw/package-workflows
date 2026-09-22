# Builds the testing-strategy guidance folded into the test-generation
# prompt. Unlike roxygen's role_guidance() (mostly about wording/framing),
# this is a genuinely different STRATEGY per role — see
# test-coverage-workflow-design-notes.md's "DATASHIELD ROLE SPLIT" section.
#
# has_existing_setup comes from detect_dslite_setup(). dslite_datasets is
# the loaded config/dslite-canned-datasets.json$datasets list, only needed
# (and only passed non-NULL) when a fresh setup.R needs to be generated —
# Claude picks which canned dataset fits via the dslite_dataset tool field,
# this function just presents the options.
build_test_role_guidance <- function(datashield, ds_type, has_existing_setup, dslite_datasets) {
  if (!isTRUE(datashield) || !identical(ds_type, "client")) {
    return(paste(
      "This function performs real local computation and should be tested",
      "in the normal R sense: call the function with realistic arguments",
      "and assert on its actual return value, not a mock.",
      sep = "\n"
    ))
  }

  if (isTRUE(has_existing_setup)) {
    return(paste(
      "This is a DataSHIELD CLIENT-side function. tests/testthat/setup.R",
      "already establishes a DSLite connection (assume a `conns` object is",
      "available exactly as that file defines it) — do NOT write your own",
      "login/connection code, and do NOT assume any specific table/dataset",
      "beyond what setup.R already assigns. Leave dslite_dataset empty —",
      "it is not used when reusing an existing setup.",
      sep = "\n"
    ))
  }

  dataset_lines <- vapply(dslite_datasets, function(d) {
    sprintf("- %s: %s Fits when: %s", d$name, d$description, d$fits_when)
  }, character(1))

  paste(
    "This is a DataSHIELD CLIENT-side function, tested against DSLite (an",
    "in-process, serverless implementation of the DataSHIELD server",
    "interface) — real execution and real assertions, not mocking. No",
    "tests/testthat/setup.R exists yet for this package, so one will be",
    "generated using one of DSLite's built-in canned datasets. Pick the",
    "single best-fitting option and return its name as dslite_dataset",
    "(exactly as written below, e.g. \"CNSIM\"):",
    "",
    paste(dataset_lines, collapse = "\n"),
    "",
    "The server-side method registration itself is automatic (DSLite",
    "discovers it from the client package alone) — you do not need to",
    "identify or name a specific server-side function for this to work.",
    sep = "\n"
  )
}
