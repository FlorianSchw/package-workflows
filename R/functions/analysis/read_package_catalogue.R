# Reads the DataSHIELD package catalogue (packages.json of
# packages.datashield.org, built from FederatedMethods/packages) into a
# named list: per package its description, status (production /
# development / retired, or "unknown" if none is given; lower case),
# GitHub and CRAN links. Returns an empty
# list, with a message, if it can't be read: the analysis then just has no
# "possible with another package" notes.
read_package_catalogue <- function(url) {
  raw <- tryCatch(jsonlite::fromJSON(url, simplifyVector = FALSE), error = function(e) {
    message(sprintf("Package catalogue %s could not be read: %s", url, conditionMessage(e)))
    NULL
  })
  if (is.null(raw)) return(list())

  lapply(raw, function(p) {
    input <- p$input
    list(
      description = if (is.null(input$description)) "" else input$description,
      status = if (is.null(input$status) || !nzchar(trimws(input$status))) "unknown" else tolower(trimws(input$status)),
      github = if (is.null(input$github_link)) "" else sub("/+$", "", input$github_link),
      cran = if (is.null(input$cran_link)) "" else input$cran_link
    )
  })
}
