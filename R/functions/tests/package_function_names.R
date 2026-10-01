# Names of the functions the package defines at the top level of its R/
# files (same definition pattern as parse_r_file()). Used to tell a
# categorised test file name, test-<category>-<function>.R, from a plain
# name that merely contains a dash.
package_function_names <- function() {
  files <- list.files("R", pattern = "\\.[Rr]$", full.names = TRUE)
  fn_def_pattern <- "^([A-Za-z._][A-Za-z0-9._]*)\\s*(<-|=)\\s*function\\s*\\("
  lines <- unlist(lapply(files, readLines, warn = FALSE))
  unique(sub(paste0(fn_def_pattern, ".*$"), "\\1", grep(fn_def_pattern, lines, value = TRUE)))
}
