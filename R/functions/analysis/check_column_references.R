# Checks the columns the code refers to as strings ("D$BMI",
# "D_complete$GENDER"): each must be a variable of the plan or an object a
# step creates (a `newobj` value anywhere in `all_code`, e.g. a derived
# variable later bound into a data frame). The test run can't catch
# unknown columns: DSLite with the permissive privacy level returns NA
# for them instead of an error. Returns the problems found.
check_column_references <- function(code, all_code, variables) {
  strings_in <- function(text, only_arg = NULL) {
    found <- character(0)
    walk_code(text, function(x, arg) {
      if (is.character(x) && length(x) == 1 && (is.null(only_arg) || arg == only_arg)) found <<- c(found, x)
    })
    found
  }

  known <- c(variables, strings_in(all_code, only_arg = "newobj"))
  refs <- grep("^[A-Za-z.][A-Za-z0-9._]*\\$[A-Za-z.][A-Za-z0-9._]*$", strings_in(code), value = TRUE)
  unknown <- unique(refs[!sub("^.*\\$", "", refs) %in% known])
  if (length(unknown) == 0) return(character(0))
  sprintf(
    "%s refers to a column that is neither a variable of the plan nor created by any step (plan variables: %s).",
    paste(sprintf("\"%s\"", unknown), collapse = ", "), paste(variables, collapse = ", ")
  )
}
