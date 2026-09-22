# Builds the DSLite login/connection preamble for a NEW client-side test
# file (no existing tests/testthat/setup.R). Uses DSLite's own built-in
# canned datasets (config/dslite-canned-datasets.json lists the options) —
# no external server, no credentials, no per-package config needed.
#
# Verified against a real run: setupCNSIMTest(packages = c(pkg)) (or the
# equivalent setup*Test() for another canned dataset) auto-discovers and
# registers that package's server-side methods (e.g. dsTidyverseClient's
# arrangeDS) with NO separate assignMethod() call needed — DSLite reads
# the method table from the installed package itself. An earlier version
# of this function assumed manual registration was required and used a
# nonexistent `.prepare_dslite()` helper (borrowed from a package's own
# private test helper, not a real DSLite API) — this is the corrected,
# actually-executed version.
build_dslite_test_snippet <- function(dataset_choice, package_name) {
  paste(
    "require('DSLite')",
    "require('DSI')",
    sprintf("require('%s')", package_name),
    "",
    sprintf(
      "logindata <- DSLite::%s(packages = c(\"%s\"))",
      dataset_choice$setup_function, package_name
    ),
    "conns <- DSI::datashield.login(logins = logindata, assign = TRUE)",
    sep = "\n"
  )
}
