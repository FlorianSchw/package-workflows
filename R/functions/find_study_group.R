# Finds the study group in datashield-example-env.json whose
# compatible_packages lists this package, or NULL if none does.
find_study_group <- function(example_env, package_name) {
  if (is.null(example_env) || is.na(package_name)) return(NULL)
  Find(function(grp) package_name %in% unlist(grp$compatible_packages), example_env$study_groups)
}
