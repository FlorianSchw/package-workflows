# Extracts the bare function name from a parsed file's header text
# (e.g. "ds.temp.test<- function(...)" -> "ds.temp.test"). parse_r_file()
# doesn't store this directly since roxygen-suggest.yml never needed it;
# test file naming (test-<function>.R) does.
extract_function_name <- function(parsed) {
  trimws(sub("\\s*(<-|=)\\s*function\\s*\\(.*$", "", parsed$fn_header))
}
