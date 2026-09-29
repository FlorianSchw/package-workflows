# Replaces every {{KEY}} placeholder in a prompt template with values[[KEY]],
# in a single pass — substituted text (function source, existing docs) is
# never re-scanned, so a value that happens to contain "{{SOMETHING}}"
# can't be mangled. Fails loudly if the template uses a placeholder with no
# value, rather than silently sending Claude a literal "{{KEY}}".
fill_template <- function(template, values) {
  if (!is.character(template) || length(template) != 1) {
    stop("fill_template() needs one text template; is an entry missing in a config or prompt file?", call. = FALSE)
  }
  matches <- gregexpr("\\{\\{[A-Z_]+\\}\\}", template)
  found <- regmatches(template, matches)[[1]]
  keys <- substr(found, 3, nchar(found) - 2)

  missing <- setdiff(unique(keys), names(values))
  if (length(missing) > 0) {
    stop(sprintf("Prompt template has no value for placeholder(s): %s", paste(missing, collapse = ", ")))
  }

  regmatches(template, matches) <- list(vapply(keys, function(k) as.character(values[[k]]), character(1)))
  template
}
