# Reads a JSON config (see resolve_shared_path() for where it's looked up).
# Optional configs return NULL when absent; required ones fail loudly here
# rather than surfacing later as a confusing error about a NULL.
read_json_config <- function(rel_path, required = FALSE) {
  path <- resolve_shared_path(rel_path)
  if (!file.exists(path)) {
    if (required) stop(sprintf("Required config not found: %s", path))
    return(NULL)
  }
  fromJSON(path, simplifyVector = FALSE)
}
