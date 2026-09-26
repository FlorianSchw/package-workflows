# Makes text from a workflow file safe inside a Mermaid label: quotes and
# angle brackets become Mermaid entities, so a name or condition can't end
# the label or be read as HTML. Only for text taken from the files — the
# diagram builders add their own <br/> and <small> around it.
mermaid_text <- function(x) {
  x <- gsub("\"", "#quot;", x, fixed = TRUE)
  x <- gsub("<", "#lt;", x, fixed = TRUE)
  gsub(">", "#gt;", x, fixed = TRUE)
}
