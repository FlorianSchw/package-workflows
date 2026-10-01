# Where a function's tests live: tests/testthat/test-<function>.R, or
# test-<category>-<function>.R in a categorised repository
# (detect_test_scheme()).
test_file_path <- function(function_name, category = NA_character_) {
  name <- if (is.na(category)) sprintf("test-%s.R", function_name) else sprintf("test-%s-%s.R", category, function_name)
  file.path("tests", "testthat", name)
}
