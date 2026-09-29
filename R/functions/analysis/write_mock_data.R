# Writes one .rda file per study into `dir`, in the form dsAnalysis's
# update_MockData() expects: <server>.rda holding an object named after the
# server. The folder belongs to the bot, so files of studies no longer in
# the plan are removed. Returns the written and removed paths (both go
# into the commit).
write_mock_data <- function(mock, dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  written <- vapply(names(mock), function(server) {
    path <- file.path(dir, paste0(server, ".rda"))
    env <- new.env()
    assign(server, mock[[server]], envir = env)
    save(list = server, envir = env, file = path)
    path
  }, character(1))
  stale <- setdiff(list.files(dir, pattern = "\\.rda$", full.names = TRUE), written)
  file.remove(stale)
  list(written = unname(written), removed = stale)
}
