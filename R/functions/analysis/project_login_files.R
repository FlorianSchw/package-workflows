# Where the project's two login files are, read from its config.yml (the
# `config` package file dsAnalysis uses to switch between the real login
# and the DSLite test setup). Falls back to the dsAnalysis template paths.
project_login_files <- function(config_file = "config.yml") {
  cfg <- tryCatch(yaml::read_yaml(config_file), error = function(e) list())
  path_of <- function(profile, folder, file) {
    p <- cfg[[profile]]
    if (!is.null(p$login_folder) && !is.null(p$login_file)) file.path(p$login_folder, p$login_file) else file.path(folder, file)
  }
  list(
    production = path_of("production", "R", "01_DS_Login.R"),
    testing = path_of("testing", file.path("utils", "setup"), "01_DSLite_Setup.R")
  )
}
