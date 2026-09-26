# Resolves a path given relative to the package-workflows repo root (e.g.
# "config/roxygen-style.json"): the caller repo's own file at that same
# relative path wins if it exists (an override — and what makes running
# directly inside package-workflows work), otherwise the copy in the
# `.shared-workflows/` checkout the suggestion workflows create. Same rule
# the entry scripts use to locate R/functions/.
resolve_shared_path <- function(rel_path) {
  if (file.exists(rel_path)) rel_path else file.path(".shared-workflows", rel_path)
}
