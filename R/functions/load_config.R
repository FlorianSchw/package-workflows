# Resolves a config/script/template path: prefers a same-named file at the
# caller repo's root (an override), falling back to this repo's own copy
# under the `.shared-workflows/` checkout that roxygen-suggest.yml creates.
load_config <- function(local_name, shared_path) {
  if (file.exists(local_name)) local_name else shared_path
}
