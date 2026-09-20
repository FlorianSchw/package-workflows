# Returns `b` when `a` is NULL, otherwise `a` — used as a safe default for
# values that may be missing or empty.
`%||%` <- function(a, b) if (is.null(a)) b else a
