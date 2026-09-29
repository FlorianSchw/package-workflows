# The server packages the analysis can use: those installed on EVERY
# study. Returns a data frame (package, version) plus notes: a package
# missing on some studies isn't usable for a pooled analysis, and
# differing versions are tested with the lowest one (the version every
# study has at least).
usable_server_packages <- function(plan) {
  per_study <- lapply(plan$studies, function(s) vapply(s$packages, as.character, character(1)))
  all_names <- unique(unlist(lapply(per_study, names)))
  notes <- character(0)
  rows <- list()

  for (p in all_names) {
    versions <- vapply(per_study, function(x) if (p %in% names(x)) x[[p]] else NA_character_, character(1))
    missing <- vapply(plan$studies, function(s) s$server, character(1))[is.na(versions)]
    if (length(missing) > 0) {
      notes <- c(notes, sprintf(
        "`%s` is not installed on %s, so it isn't used; functions from it would only work if those studies are left out.",
        p, paste(sprintf("`%s`", missing), collapse = ", ")
      ))
      next
    }
    if (length(unique(versions)) > 1) {
      lowest <- as.character(min(numeric_version(versions)))
      notes <- c(notes, sprintf("`%s` has different versions on the studies (%s); tested with the lowest, %s.", p, paste(unique(versions), collapse = ", "), lowest))
      versions <- lowest
    }
    rows[[length(rows) + 1]] <- data.frame(package = p, version = versions[[1]])
  }

  list(packages = if (length(rows) > 0) do.call(rbind, rows) else data.frame(package = character(0), version = character(0)), notes = notes)
}
