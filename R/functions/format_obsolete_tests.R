# Markdown list of existing tests Claude suggests deleting, for the test
# report. Nothing is deleted automatically. Entries whose description
# doesn't appear in the existing test file are dropped — Claude must name
# a real test, not invent one.
format_obsolete_tests <- function(obsolete, existing_content, function_name) {
  real <- Filter(function(o) {
    found <- nzchar(o$description) && grepl(o$description, existing_content, fixed = TRUE)
    if (!found) message(sprintf("%s: ignoring obsolete-test suggestion '%s' — no such test.", function_name, o$description))
    found
  }, obsolete)

  vapply(real, function(o) {
    sprintf("- `%s`: \"%s\" — `%s`. %s", function_name, o$description, o$reason, o$explanation)
  }, character(1))
}
