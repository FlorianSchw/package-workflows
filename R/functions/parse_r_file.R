# Parses a single R file to locate its (first) function definition and the
# roxygen block immediately preceding it (if any), plus enough structural
# detail (name, params, the blank-line gap between block and function, the
# existing block's tag lines) for both suggestion workflows to build their
# review requests and write results back.
parse_r_file <- function(path) {
  lines <- readLines(path, warn = FALSE)
  fn_def_pattern <- "^([A-Za-z._][A-Za-z0-9._]*)\\s*(<-|=)\\s*function\\s*\\("
  fn_line_idx <- grep(fn_def_pattern, lines)
  if (length(fn_line_idx) == 0) return(NULL)
  if (length(fn_line_idx) > 1) {
    warning(sprintf(
      "%s: found %d function definitions; only checking the first. Convention assumes one per file.",
      path, length(fn_line_idx)
    ))
  }
  fn_start <- fn_line_idx[1]
  fn_name <- sub(paste0(fn_def_pattern, ".*$"), "\\1", lines[fn_start])

  header_text <- lines[fn_start]
  open_count  <- lengths(regmatches(header_text, gregexpr("\\(", header_text)))
  close_count <- lengths(regmatches(header_text, gregexpr("\\)", header_text)))
  header_end  <- fn_start
  while (open_count > close_count && header_end < length(lines)) {
    header_end <- header_end + 1
    header_text <- paste(header_text, lines[header_end])
    open_count  <- lengths(regmatches(header_text, gregexpr("\\(", header_text)))
    close_count <- lengths(regmatches(header_text, gregexpr("\\)", header_text)))
  }

  args_str <- sub(fn_def_pattern, "", header_text)
  args_str <- sub("\\)[^)]*$", "", args_str)

  split_args <- function(s) {
    if (!nzchar(trimws(s))) return(character(0))
    depth <- 0; parts <- character(0); buf <- ""
    for (ch in strsplit(s, "")[[1]]) {
      if (ch %in% c("(", "[")) depth <- depth + 1
      if (ch %in% c(")", "]")) depth <- depth - 1
      if (ch == "," && depth == 0) { parts <- c(parts, buf); buf <- "" } else { buf <- paste0(buf, ch) }
    }
    c(parts, buf)
  }
  params <- trimws(vapply(split_args(args_str), function(a) sub("=.*$", "", a), character(1), USE.NAMES = FALSE))
  params <- params[nzchar(params)]

  gap_end <- fn_start - 1
  while (gap_end >= 1 && !nzchar(trimws(lines[gap_end]))) gap_end <- gap_end - 1

  rox_end <- gap_end
  rox_start <- rox_end
  while (rox_start >= 1 && grepl("^\\s*#'", lines[rox_start])) rox_start <- rox_start - 1
  rox_start <- rox_start + 1
  has_roxygen <- rox_start <= rox_end
  roxygen_lines <- if (has_roxygen) lines[rox_start:rox_end] else character(0)

  pre_end <- if (has_roxygen) rox_start - 1 else fn_start - 1
  gap_lines <- if (has_roxygen && (rox_end + 1) <= (fn_start - 1)) {
    lines[(rox_end + 1):(fn_start - 1)]
  } else {
    character(0)
  }

  body_text <- if (length(roxygen_lines) > 0) sub("^\\s*#'\\s?", "", roxygen_lines) else character(0)
  is_exported <- any(grepl("^@export\\b", body_text))

  # Each tag together with its continuation lines (everything up to the next
  # @tag, as roxygen itself reads them), kept as the original raw lines so
  # they can be carried forward byte-for-byte. Trailing blank lines are
  # dropped; text before the first tag (an untagged title/description) isn't
  # part of any chunk.
  tag_chunks <- list()
  for (i in seq_along(body_text)) {
    if (grepl("^@[A-Za-z]", body_text[i])) {
      tag_chunks[[length(tag_chunks) + 1]] <- list(
        tag = sub("^@([A-Za-z][A-Za-z0-9]*).*$", "\\1", body_text[i]),
        text = body_text[i],
        lines = roxygen_lines[i]
      )
    } else if (length(tag_chunks) > 0) {
      n <- length(tag_chunks)
      tag_chunks[[n]]$text  <- c(tag_chunks[[n]]$text, body_text[i])
      tag_chunks[[n]]$lines <- c(tag_chunks[[n]]$lines, roxygen_lines[i])
    }
  }
  tag_chunks <- lapply(tag_chunks, function(ch) {
    last_content <- max(which(nzchar(trimws(ch$text))))
    list(tag = ch$tag, lines = ch$lines[seq_len(last_content)])
  })

  list(
    lines = lines, fn_start = fn_start, fn_name = fn_name, fn_header = header_text, params = params,
    has_roxygen = has_roxygen,
    roxygen_start = if (has_roxygen) rox_start else fn_start,
    roxygen_end = if (has_roxygen) rox_end else fn_start - 1,
    roxygen_lines = roxygen_lines,
    pre_end = pre_end,
    gap_lines = gap_lines,
    is_exported = is_exported,
    tag_chunks = tag_chunks
  )
}
