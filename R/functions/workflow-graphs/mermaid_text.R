# Makes text from a workflow file safe inside a Mermaid label: quotes,
# angle brackets and asterisks become Mermaid entities, so a name or
# condition can't end the label, be read as HTML, or turn "R/**" into bold
# text. Only for text taken from the files — the diagram builders add
# their own <br/> around it.
mermaid_text <- function(x) {
  x <- gsub("\"", "#quot;", x, fixed = TRUE)
  x <- gsub("*", "#42;", x, fixed = TRUE)
  x <- gsub("<", "#lt;", x, fixed = TRUE)
  gsub(">", "#gt;", x, fixed = TRUE)
}
