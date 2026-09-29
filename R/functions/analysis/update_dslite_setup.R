# Points the project's DSLite test setup at the bot's mock data and adds
# missing server packages, using dsAnalysis's own functions
# (update_MockData(), add_dsPackage()), sourced from a checkout of the
# dsAnalysis repository, so dsAnalysis stays the only owner of that file's
# format. Returns the setup file's path, or NULL with a message if the
# project has no DSLite setup or dsAnalysis isn't available.
#
# add_dsPackage() breaks the file when every given package is already
# there (dev-notes/analysis-suggest.md, dsAnalysis checklist), so it is
# only called with packages its own check wouldn't find.
update_dslite_setup <- function(setup_file, dsanalysis_dir, mock_folder, server_packages) {
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

  servers <- sub("\\.rda$", "", list.files(file.path("utils", "mock_data", mock_folder), pattern = "\\.rda$"))
  env$update_MockData(folder_name = mock_folder, table_names = servers)

  lines <- readLines(setup_file, warn = FALSE)
  block1 <- lines[seq_len(which(lines == "#### Step 2: Import of mock data files")[1] - 1)]
  missing <- server_packages[!vapply(server_packages, function(p) any(grepl(p, block1, fixed = TRUE)), logical(1))]
  if (length(missing) > 0) env$add_dsPackage(missing)

  setup_file
}
