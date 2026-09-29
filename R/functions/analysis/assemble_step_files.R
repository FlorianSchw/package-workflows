# Builds a step's script files from Claude's sections: a marker line, a
# short header, then each section as "#### <purpose>" plus its code.
# Files hold at most `max_lines` lines; longer steps are split between
# sections into 02a_, 02b_, ... A single section longer than the limit
# gets a file of its own (and a note), never cut in half.
# A step with no sections (nothing possible with the installed packages)
# still gets a file, with its `step_notes` as comments only: the analyst
# sees the gap where the code would go, and the marker line keeps the step
# from being requested again until its plan entry changes.
# Returns list(files = list of list(path, lines), notes).
assemble_step_files <- function(step, sections, number, plan_hash, max_lines, tested_with, plan_file, step_notes = list()) {
  header <- c(
    sprintf("#### %s", step$title),
    sprintf("#### Drafted by the datashield-analysis-suggest workflow from %s.", plan_file),
    "#### A starting point: check and adapt it. The analysis is your responsibility.",
    sprintf("#### Tested with %s, on mock data in DSLite.", tested_with),
    ""
  )
  blocks <- lapply(sections, function(s) {
    code <- sub("\\s+$", "", strsplit(sub("\\n+$", "", s$code), "\n", fixed = TRUE)[[1]])
    c(sprintf("#### %s", gsub("\\s+", " ", trimws(s$purpose))), code, "")
  })
  if (length(blocks) == 0) {
    blocks <- list(c(
      "#### No code: this step isn't possible with the packages on your study servers.",
      vapply(step_notes, function(n) sprintf("#### - %s", gsub("\\s+", " ", n$text)), character(1))
    ))
  }

  budget <- max_lines - 1 - length(header)  # marker line and header count too
  parts <- list()
  current <- character(0)
  notes <- character(0)
  for (b in blocks) {
    if (length(current) > 0 && length(current) + length(b) > budget) {
      parts[[length(parts) + 1]] <- current
      current <- character(0)
    }
    if (length(b) > budget) {
      notes <- c(notes, sprintf("A section of step `%s` is longer than %d lines and has a file of its own.", step$id, max_lines))
    }
    current <- c(current, b)
  }
  if (length(current) > 0) parts[[length(parts) + 1]] <- current

  letters_used <- if (length(parts) > 1) letters[seq_along(parts)] else ""
  title <- script_file_title(step$title)
  files <- lapply(seq_along(parts), function(i) {
    body <- c(header, sub("\\n$", "", parts[[i]]))
    while (length(body) > 0 && body[length(body)] == "") body <- body[-length(body)]
    marker <- sprintf("#### bot-suggest: step=%s plan=%s content=%s", step$id, plan_hash, text_hash(body))
    list(path = file.path("R", sprintf("%s%s_%s.R", number, letters_used[i], title)), lines = c(marker, body))
  })
  list(files = files, notes = notes)
}
