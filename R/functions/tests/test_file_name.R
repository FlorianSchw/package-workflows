# The name an R file's tests are named after: its file name without .R
# (see test_file_path()).
test_file_name <- function(r_file) {
  sub("[.][Rr]$", "", basename(r_file))
}
