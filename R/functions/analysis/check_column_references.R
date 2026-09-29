# Checks the columns the code refers to as strings ("D$BMI",
# "D_complete$GENDER"): each must be a variable of the plan or an object a
# step creates (a `newobj` value anywhere in `all_code`, e.g. a derived
# variable later bound into a data frame). The test run can't catch
# unknown columns: DSLite with the permissive privacy level returns NA
# for them instead of an error. Returns the problems found.
check_column_references <- function(code, all_code, variables) {
  strings_of <- function(text, newobj_only = FALSE) {
    exprs <- tryCatch(parse(text = text, keep.source = FALSE), error = function(e) NULL)
    found <- character(0)
    visit <- function(x, arg = "") {
      if (is.character(x) && length(x) == 1 && (!newobj_only || arg == "newobj")) found <<- c(found, x)
      if (is.call(x)) {
        args <- as.list(x)[-1]
        arg_names <- if (is.null(names(args))) rep("", length(args)) else names(args)
        for (i in seq_along(args)) if (!identical(args[[i]], quote(expr = ))) visit(args[[i]], arg_names[i])
      }
    }
    for (e in exprs) visit(e)
    found
  }

  known <- c(variables, strings_of(all_code, newobj_only = TRUE))
  refs <- grep("^[A-Za-z.][A-Za-z0-9._]*\\$[A-Za-z.][A-Za-z0-9._]*$", strings_of(code), value = TRUE)
  unknown <- unique(refs[!sub("^.*\\$", "", refs) %in% known])
  if (length(unknown) == 0) return(character(0))
  sprintf(
    "%s refers to a column that is neither a variable of the plan nor created by any step (plan variables: %s).",
    paste(sprintf("\"%s\"", unknown), collapse = ", "), paste(variables, collapse = ", ")
  )
}
