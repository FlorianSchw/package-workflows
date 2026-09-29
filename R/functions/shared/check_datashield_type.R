# Stops the run when a DataSHIELD package names an unknown datashield-type,
# so a typo fails loudly instead of silently dropping the role guidance.
check_datashield_type <- function(datashield, ds_type) {
  allowed <- c("client", "server", "utility")
  if (isTRUE(datashield) && !ds_type %in% allowed) {
    stop(sprintf(
      "datashield is true, but datashield-type is '%s' — it must be one of: %s.",
      ds_type, paste(allowed, collapse = ", ")
    ), call. = FALSE)
  }
  invisible(TRUE)
}
