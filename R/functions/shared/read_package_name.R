# The calling repo's package name from its DESCRIPTION, or NA if it can't
# be read.
read_package_name <- function() {
  tryCatch(
    as.character(read.dcf("DESCRIPTION")[1, "Package"]),
    error = function(e) NA_character_
  )
}
