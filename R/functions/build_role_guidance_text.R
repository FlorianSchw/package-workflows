# Reassembles a role-guidance config entry (intro/documentation/closing,
# each an array of lines in datashield-role-guidance.json) into one prose
# paragraph.
build_role_guidance_text <- function(cfg) {
  if (is.null(cfg)) return("")
  join <- function(x) paste(unlist(x), collapse = " ")
  doc <- cfg$documentation
  parts <- c(
    join(cfg$intro),
    sprintf("- param docs: %s", join(doc$param)),
    sprintf("- return doc: %s", join(doc$return)),
    sprintf("- details: %s", join(doc$details))
  )
  if (!is.null(cfg$closing) && length(cfg$closing) > 0) {
    parts <- c(parts, join(cfg$closing))
  }
  paste(parts, collapse = "\n")
}
