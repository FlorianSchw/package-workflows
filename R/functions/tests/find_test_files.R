# All existing test files of a function: test-<function>.R — in any
# repository, categorised or not — and every test-<category>-<function>.R
# that detect_test_scheme() assigned to it (`scheme$files`), also in a
# plain repository. Matched exactly, so `ds.mean` never picks up
# `ds.meanByClass`. Returns a list of read_test_file() entries, empty if
# the function has no tests yet.
find_test_files <- function(function_name, scheme) {
  plain <- read_test_file(test_file_path(function_name))
  mine <- scheme$files[scheme$files$fn == function_name, , drop = FALSE]
  categorised <- lapply(seq_len(nrow(mine)), function(i) read_test_file(mine$path[i], mine$category[i]))
  Filter(function(x) x$exists, c(list(plain), categorised))
}
