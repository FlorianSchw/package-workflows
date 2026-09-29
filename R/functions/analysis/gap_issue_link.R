# A prefilled "Open issue" link for a function no known DataSHIELD package
# offers. The analyst opens the issue under their own account, after
# seeing what gets published, so no token is needed and nothing about the
# project is posted automatically. Only the step title and the note go
# into the issue, not the plan.
gap_issue_link <- function(repo, step_title, note_text) {
  title <- sprintf("Missing DataSHIELD function: %s", substr(note_text, 1, 80))
  body <- paste(
    "Reported from the DataSHIELD analysis starter (datashield-analysis-suggest).",
    "",
    sprintf("**Analysis step:** %s", step_title),
    "",
    sprintf("**What is missing:** %s", note_text),
    "",
    "_Please add what you would need, e.g. the method, its inputs and outputs._",
    sep = "\n"
  )
  sprintf(
    "https://github.com/%s/issues/new?title=%s&body=%s",
    repo, utils::URLencode(title, reserved = TRUE), utils::URLencode(body, reserved = TRUE)
  )
}
