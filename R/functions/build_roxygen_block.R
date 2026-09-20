# Deterministic assembly: the ONLY place the final roxygen block is built,
# from Claude's prose fields, in the exact order given by tag_order.
build_roxygen_block <- function(result, parsed, path) {
  order <- unlist(style$tag_order)
  sections <- list()

  wrap <- function(text) {
    paste0("#' ", strsplit(text, "\n")[[1]])
  }

  title       <- sanitize_field(result$title, "title", path)
  description <- sanitize_field(result$description, "description", path)
  details     <- sanitize_field(result$details, "details", path)
  return_doc  <- sanitize_field(result$return_doc, "return_doc", path)
  examples_body <- sanitize_field(result$examples_body, "examples_body", path)

  if (!nzchar(trimws(title))) {
    stop(sprintf("%s: 'title' field was empty after sanitization — Claude's response likely contained only roxygen artifacts with no real title.", path))
  }
  if (!nzchar(trimws(description))) {
    stop(sprintf("%s: 'description' field was empty after sanitization — Claude's response likely contained only roxygen artifacts with no real description.", path))
  }

  for (tag in order) {
    if (tag == "title") {
      sections[["title"]] <- wrap(paste0("@title ", title))
    } else if (tag == "description") {
      sections[["description"]] <- wrap(paste0("@description ", description))
    } else if (tag == "details" && nzchar(trimws(details))) {
      sections[["details"]] <- wrap(paste0("@details ", details))
    } else if (tag == "param") {
      param_lines <- character(0)
      for (p in parsed$params) {
        doc <- result$params[[p]]
        if (is.null(doc)) {
          stop(sprintf("Claude's response is missing documentation for parameter '%s'.", p))
        }
        doc <- sanitize_field(doc, sprintf("param.%s", p), path)
        if (!nzchar(trimws(doc))) {
          stop(sprintf("%s: documentation for parameter '%s' was empty after sanitization.", path, p))
        }
        param_lines <- c(param_lines, wrap(paste0("@param ", p, " ", doc)))
      }
      sections[["param"]] <- param_lines
    } else if (tag == "return") {
      sections[["return"]] <- wrap(paste0("@return ", return_doc))
    } else if (tag == "import") {
      import_lines <- parsed$passthrough_lines[grepl("^@import\\b(?!From)", parsed$passthrough_lines, perl = TRUE)]
      if (length(import_lines) > 0) sections[["import"]] <- paste0("#' ", import_lines)
    } else if (tag == "importFrom") {
      importfrom_lines <- parsed$passthrough_lines[grepl("^@importFrom\\b", parsed$passthrough_lines)]
      if (length(importfrom_lines) > 0) sections[["importFrom"]] <- paste0("#' ", importfrom_lines)
    } else if (tag == "examples" && nzchar(trimws(examples_body))) {
      ex_lines <- strsplit(examples_body, "\n")[[1]]
      examples_open <- "#' \\dontrun"
      sections[["examples"]] <- c(
        "#' @examples",
        paste0(examples_open, "{"),
        paste0("#' ", ex_lines),
        "#' }"
      )
    } else if (tag == "export") {
      export_lines <- parsed$passthrough_lines[grepl("^@export\\b", parsed$passthrough_lines)]
      if (length(export_lines) > 0) sections[["export"]] <- paste0("#' ", export_lines)
    }
  }

  paste(unlist(sections, use.names = FALSE), collapse = "\n")
}
