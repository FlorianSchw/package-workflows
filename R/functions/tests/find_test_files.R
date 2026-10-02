# All existing test files of an R file (`name`: its file name without .R,
# test_file_name()): test-<name>.R — in any repository, categorised or not
# — and every test-<category>-<name>.R that detect_test_scheme() assigned
# to it (`scheme$files`), also in a plain repository. Matched exactly, so
# `ds.mean` never picks up `ds.meanByClass`. Returns a list of
# read_test_file() entries, empty if there are no tests yet.
find_test_files <- function(name, scheme) {
  plain <- read_test_file(test_file_path(name))
  mine <- scheme$files[scheme$files$fn == name, , drop = FALSE]
  categorised <- lapply(seq_len(nrow(mine)), function(i) read_test_file(mine$path[i], mine$category[i]))
  Filter(function(x) x$exists, c(list(plain), categorised))
}
