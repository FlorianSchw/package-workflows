# The server packages the analysis can use: those installed on EVERY
# study. Returns a data frame (package, version) plus notes (wording from
# `texts$notes`): a package missing on some studies isn't usable for a
# pooled analysis, and differing versions are tested with the lowest one
# (the version every study has at least).
usable_server_packages <- function(plan, texts) {
  per_study <- lapply(plan$studies, function(s) vapply(s$packages, as.character, character(1)))
  servers <- vapply(plan$studies, function(s) s$server, character(1))
  notes <- character(0)
  rows <- list()

  for (p in unique(unlist(lapply(per_study, names)))) {
    versions <- vapply(per_study, function(x) if (p %in% names(x)) x[[p]] else NA_character_, character(1))
    if (anyNA(versions)) {
      notes <- c(notes, fill_template(texts$notes$package_missing_on_studies, list(
        PACKAGE = p, STUDIES = paste(sprintf("`%s`", servers[is.na(versions)]), collapse = ", ")
      )))
      next
    }
    version <- versions[[1]]
    if (length(unique(versions)) > 1) {
      version <- as.character(min(numeric_version(versions)))
      notes <- c(notes, fill_template(texts$notes$package_versions_differ, list(
        PACKAGE = p, VERSIONS = paste(unique(versions), collapse = ", "), LOWEST = version
      )))
    }
    rows[[length(rows) + 1]] <- data.frame(package = p, version = version)
  }

  list(packages = if (length(rows) > 0) do.call(rbind, rows) else data.frame(package = character(0), version = character(0)), notes = notes)
}
