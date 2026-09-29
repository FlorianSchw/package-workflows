# Installs a DataSHIELD package at a given version and returns what was
# installed: list(package, requested, installed, ref, note). Most
# DataSHIELD packages are only on GitHub, so the sources are tried in this
# order (dev-notes/analysis-suggest.md, "Package versions"):
#   1. CRAN (incl. archive), if the catalogue lists a CRAN link;
#   2. a GitHub tag "v<version>", then "<version>";
#   3. the GitHub default branch — its version is then compared.
# A version that doesn't match, or no install at all, becomes a note for
# the report; the run goes on with what is installed.
install_ds_package <- function(package, version, catalogue) {
  entry <- catalogue[[package]]
  repo <- if (!is.null(entry) && nzchar(entry$github)) sub("^https?://github.com/", "", entry$github) else NA_character_
  refs <- c(
    if (is.null(entry) || nzchar(entry$cran)) sprintf("%s@%s", package, version),
    if (!is.na(repo)) c(sprintf("%s@v%s", repo, version), sprintf("%s@%s", repo, version), repo)
  )

  installed_version <- function() {
    tryCatch(as.character(utils::packageVersion(package, lib.loc = .libPaths())), error = function(e) NA_character_)
  }

  for (ref in refs) {
    ok <- tryCatch({
      pak::pkg_install(ref, ask = FALSE, upgrade = FALSE)
      TRUE
    }, error = function(e) {
      message(sprintf("Installing %s from %s failed: %s", package, ref, conditionMessage(e)))
      FALSE
    })
    if (!ok) next
    got <- installed_version()
    note <- if (!identical(got, version)) {
      sprintf("`%s` %s could not be found; tested with %s from `%s` instead.", package, version, got, ref)
    }
    return(list(package = package, requested = version, installed = got, ref = ref, note = note))
  }

  list(
    package = package, requested = version, installed = NA_character_, ref = NA_character_,
    note = sprintf("`%s` %s could not be installed from CRAN or GitHub, so it wasn't used.", package, version)
  )
}
