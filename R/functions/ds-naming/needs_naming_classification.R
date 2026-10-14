# Which classified rows the code can't settle and Claude should look at:
# low confidence, unknown role, an object of unknown class, or a name the
# rules forbid (too generic, e.g. `data`, used for several classes).
needs_naming_classification <- function(rows, rules) {
  rows$source != "claude" & rows$arg != "..." & (
    rows$confidence == "low" | rows$role == "unknown" |
      (rows$role == "object" & !nzchar(rows$class)) |
      rows$arg %in% unlist(rules$style$forbidden_names)
  )
}
