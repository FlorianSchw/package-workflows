# Formats a style profile's per-tag guidance into a bulleted list for the
# review prompt.
build_guidance_text <- function(profile) {
  parts <- vapply(names(profile), function(tag) sprintf("- %s: %s", tag, profile[[tag]]$guidance), character(1))
  paste(parts, collapse = "\n")
}
