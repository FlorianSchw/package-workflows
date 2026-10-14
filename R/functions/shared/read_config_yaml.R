# Reads a YAML config (e.g. config/analysis-texts.yml) as the shared
# defaults with the project's own file at the same path merged over them,
# key by key (utils::modifyList(): nested entries merge, lists and values
# are replaced). A project only writes what it changes, and keys added to
# the defaults later still reach projects with an older copy. Inside this
# repository (no .shared-workflows/) the file is read as it is.
read_config_yaml <- function(rel_path) {
  shared <- file.path(".shared-workflows", rel_path)
  defaults <- if (file.exists(shared)) yaml::read_yaml(shared) else list()
  own <- if (file.exists(rel_path)) yaml::read_yaml(rel_path) else list()
  if (length(defaults) == 0 && length(own) == 0) stop(sprintf("Config not found: %s", rel_path), call. = FALSE)
  utils::modifyList(defaults, if (is.null(own)) list() else own)
}
