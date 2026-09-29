# A prefilled "Open issue" link for a function no known DataSHIELD package
# offers. The analyst opens the issue under their own account, after
# seeing what gets published, so no token is needed and nothing about the
# project is posted automatically. Only the step title and the note go
# into the issue (`texts$issue`), not the plan.
gap_issue_link <- function(repo, step_title, note_text, texts) {
  values <- list(STEP = step_title, NOTE = note_text)
  title <- fill_template(texts$issue$title, list(STEP = step_title, NOTE = substr(note_text, 1, 80)))
  body <- fill_template(texts$issue$body, values)
  sprintf(
    "https://github.com/%s/issues/new?title=%s&body=%s",
    repo, utils::URLencode(title, reserved = TRUE), utils::URLencode(body, reserved = TRUE)
  )
}
