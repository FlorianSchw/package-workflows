# A Mermaid node ID from a prefix and a name (file name, job ID): only
# letters, digits and underscores, and always prefixed, so a job called
# "end" or "graph" can't collide with Mermaid keywords.
mermaid_id <- function(prefix, name) {
  paste0(prefix, "_", gsub("[^A-Za-z0-9]", "_", name))
}
