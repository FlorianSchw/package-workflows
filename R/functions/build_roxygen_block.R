# Deterministic assembly: the ONLY place the final roxygen block is built,
# in the order given by tag_order. Only the tags in `managed` are written
# from Claude's fields; every other tag in the original block (@export,
# @author, @seealso, @rdname, ... — including ones nobody anticipated) is
# carried forward verbatim with all its lines, so nothing a package author
# wrote is ever silently dropped. Tags not named in tag_order go where its
# "*" entry is (appended at the end if there is none), in original order.
build_roxygen_block <- function(result, parsed, path) {
  managed <- c("title", "description", "details", "param", "return", "examples")
  order <- unlist(style$tag_order)
  if (!"*" %in% order) order <- c(order, "*")
  carried <- Filter(function(ch) !ch$tag %in% managed, parsed$tag_chunks)
  carried_lines <- function(keep) unlist(lapply(Filter(keep, carried), `[[`, "lines"), use.names = FALSE)
  sections <- list()

  wrap <- function(text) {
    paste0("#' ", strsplit(text, "\n")[[1]])
  }
  clean <- function(text, field_name) {
    strip_artifact_lines(text, "^\\s*(#'|@[A-Za-z]+\\b)", "roxygen syntax (comment markers or tag labels)", field_name, path)
  }

  title         <- clean(result$title, "title")
  description   <- clean(result$description, "description")
  details       <- clean(result$details, "details")
  return_doc    <- clean(result$return_doc, "return_doc")
  examples_body <- clean(result$examples_body, "examples_body")

  if (!nzchar(trimws(title))) {
    stop(sprintf("%s: 'title' field was empty after sanitization — Claude's response likely contained only roxygen artifacts with no real title.", path))
  }
  if (!nzchar(trimws(description))) {
    stop(sprintf("%s: 'description' field was empty after sanitization — Claude's response likely contained only roxygen artifacts with no real description.", path))
  }

  for (tag in order) {
    if (tag == "*") {
      sections[["*"]] <- carried_lines(function(ch) !ch$tag %in% order)
    } else if (!tag %in% managed) {
      sections[[tag]] <- carried_lines(function(ch) ch$tag == tag)
    } else if (tag == "title") {
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
        doc <- clean(doc, sprintf("param.%s", p))
        if (!nzchar(trimws(doc))) {
          stop(sprintf("%s: documentation for parameter '%s' was empty after sanitization.", path, p))
        }
        param_lines <- c(param_lines, wrap(paste0("@param ", p, " ", doc)))
      }
      sections[["param"]] <- param_lines
    } else if (tag == "return") {
      sections[["return"]] <- wrap(paste0("@return ", return_doc))
    } else if (tag == "examples" && nzchar(trimws(examples_body))) {
      sections[["examples"]] <- c(
        "#' @examples",
        "#' \\dontrun{",
        paste0("#' ", strsplit(examples_body, "\n")[[1]]),
        "#' }"
      )
    }
  }

  paste(unlist(sections, use.names = FALSE), collapse = "\n")
}
