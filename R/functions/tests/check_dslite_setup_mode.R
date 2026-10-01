# Stops the run on an unknown dslite-setup value, so a typo fails loudly
# instead of silently creating (or not creating) a setup.
check_dslite_setup_mode <- function(mode) {
  allowed <- c("auto", "create", "never")
  if (!mode %in% allowed) {
    stop(sprintf("dslite-setup is '%s' — it must be one of: %s.", mode, paste(allowed, collapse = ", ")), call. = FALSE)
  }
  invisible(TRUE)
}
