# Points the project's DSLite test setup at the bot's mock data and adds
# missing server packages, using dsAnalysis's own functions
# (update_MockData(), add_dsPackage()), sourced from a checkout of the
# dsAnalysis repository, so dsAnalysis stays the only owner of that file's
# format. Returns the setup file's path, or NULL with a message if the
# project has no DSLite setup or dsAnalysis isn't available.
#
# add_dsPackage() breaks the file when every given package is already
# there (dev-notes/analysis-suggest.md, dsAnalysis checklist), so it is
# only called with packages its own check wouldn't find: those not named
# in the lines above `mock_data_marker` (the library() calls).
# `mock_folder` is the mock data's folder name (update_MockData() looks
# for it under utils/mock_data), `servers` the studies it holds files for.
update_dslite_setup <- function(setup_file, dsanalysis_dir, mock_folder, servers, server_packages, mock_data_marker) {
  if (!file.exists(setup_file)) {
    message(sprintf("No DSLite setup at %s — skipping its update.", setup_file))
    return(NULL)
  }
  sources <- file.path(dsanalysis_dir, "R", c("update_MockData.R", "add_dsPackage.R"))
  if (!all(file.exists(sources))) {
    message(sprintf("dsAnalysis functions not found in %s — skipping the DSLite setup update.", dsanalysis_dir))
    return(NULL)
  }
  env <- new.env()
  for (f in sources) sys.source(f, envir = env)

  # update_MockData() pairs the files it lists with these names, in
  # list.files() order: byte order, as sort(method = "radix") gives.
  env$update_MockData(folder_name = mock_folder, table_names = sort(servers, method = "radix"))

  lines <- readLines(setup_file, warn = FALSE)
  marker_line <- which(lines == mock_data_marker)
  block1 <- if (length(marker_line) > 0) lines[seq_len(marker_line[1] - 1)] else lines
  missing <- server_packages[!vapply(server_packages, function(p) any(grepl(p, block1, fixed = TRUE)), logical(1))]
  if (length(missing) > 0) env$add_dsPackage(missing)

  setup_file
}
