# How the repository names its test files, for the prompt. Plain
# repositories: new tests go into test-<function>.R. Categorised ones
# (detect_test_scheme()): Claude picks a category per new test, explained
# with the meanings from config/test-categories.json (`meanings`, a named
# list); categories without a meaning are named with a pointer to their
# existing files. Marks which categories this function already has a
# file for (`existing_files`, from find_test_files()).
format_test_scheme_guidance <- function(scheme, meanings, function_name, existing_files) {
  if (!isTRUE(scheme$categorised)) {
    return(sprintf("New tests go into `%s`.", basename(test_file_path(function_name))))
  }
  has_file <- vapply(existing_files, function(f) f$category, character(1))
  lines <- vapply(scheme$categories, function(cat) {
    meaning <- if (is.null(meanings[[cat]])) sprintf("(no description; see the repository's existing `test-%s-*.R` files)", cat) else meanings[[cat]]
    sprintf("- `%s`: %s%s", cat, meaning, if (cat %in% has_file) sprintf(" This function already has `%s`.", basename(test_file_path(function_name, cat))) else "")
  }, character(1))
  paste(c(
    sprintf("This repository names its test files `test-<category>-<function>.R`, one file per purpose. Give each new test the category that fits; the script writes it into `test-<category>-%s.R` and creates that file if needed. The categories:", function_name),
    lines
  ), collapse = "\n")
}
