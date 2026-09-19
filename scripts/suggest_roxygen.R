#!/usr/bin/env Rscript
# Reads files_to_check.txt (produced by the calling workflow), reviews each
# function's roxygen2 documentation for completeness AND accuracy against
# style guidance (and, for DataSHIELD packages, role-specific guidance), and
# either posts a GitHub PR suggestion comment (SCAN_MODE=changed) or rewrites
# the file in place (SCAN_MODE=all, caller commits + opens a PR).
#
# Claude never assembles the final roxygen text: it returns individual prose
# fields (title, description, per-param docs, return, examples), and this
# script deterministically stitches them into one block in the configured
# tag order. @export/@import/@importFrom lines are carried forward verbatim
# from the original file and never pass through Claude at all.

library(httr2)
library(jsonlite)

`%||%` <- function(a, b) if (is.null(a)) b else a

scan_mode     <- Sys.getenv("SCAN_MODE", "changed")
pr_number     <- Sys.getenv("PR_NUMBER")
pr_head_sha   <- Sys.getenv("PR_HEAD_SHA")
repo          <- Sys.getenv("GITHUB_REPOSITORY")
api_key       <- Sys.getenv("ANTHROPIC_API_KEY")
gh_token      <- Sys.getenv("GH_TOKEN")
datashield    <- as.logical(Sys.getenv("DATASHIELD", "false"))
ds_type       <- Sys.getenv("DATASHIELD_TYPE", "")

if (isTRUE(datashield) && !ds_type %in% c("client", "server")) {
  message("DATASHIELD is true but DATASHIELD_TYPE is not 'client' or 'server' — skipping role-specific guidance.")
}

load_config <- function(local_name, shared_path) {
  if (file.exists(local_name)) local_name else shared_path
}

style <- fromJSON(
  load_config("roxygen-style.json", ".shared-workflows/config/roxygen-style.json"),
  simplifyVector = FALSE
)

example_env <- NULL
if (isTRUE(datashield) && identical(ds_type, "client")) {
  env_path <- load_config("datashield-example-env.json", ".shared-workflows/config/datashield-example-env.json")
  if (file.exists(env_path)) example_env <- fromJSON(env_path, simplifyVector = FALSE)
}

package_name <- tryCatch({
  desc <- read.dcf("DESCRIPTION")
  as.character(desc[1, "Package"])
}, error = function(e) NA_character_)

matched_group <- NULL
if (!is.null(example_env) && !is.na(package_name)) {
  for (grp in example_env$study_groups) {
    if (package_name %in% unlist(grp$compatible_packages)) { matched_group <- grp; break }
  }
  if (is.null(matched_group)) {
    message(sprintf("No compatible demo study group found for package '%s' — skipping canonical example guidance.", package_name))
  }
}

files <- readLines("files_to_check.txt")
files <- files[nzchar(files)]

# --- Parsing -----------------------------------------------------------

parse_r_file <- function(path) {
  lines <- readLines(path, warn = FALSE)
  fn_line_idx <- grep("^[A-Za-z._][A-Za-z0-9._]*\\s*(<-|=)\\s*function\\s*\\(", lines)
  if (length(fn_line_idx) == 0) return(NULL)
  if (length(fn_line_idx) > 1) {
    warning(sprintf(
      "%s: found %d function definitions; only checking the first. Convention assumes one per file.",
      path, length(fn_line_idx)
    ))
  }
  fn_start <- fn_line_idx[1]

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

  args_str <- sub("^[A-Za-z._][A-Za-z0-9._]*\\s*(<-|=)\\s*function\\s*\\(", "", header_text)
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
  passthrough_lines <- body_text[grepl("^@(export|import|importFrom)\\b", body_text)]

  list(
    lines = lines, fn_start = fn_start, fn_header = header_text, params = params,
    has_roxygen = has_roxygen,
    roxygen_start = if (has_roxygen) rox_start else fn_start,
    roxygen_end = if (has_roxygen) rox_end else fn_start - 1,
    roxygen_lines = roxygen_lines,
    pre_end = pre_end,
    gap_lines = gap_lines,
    is_exported = is_exported,
    passthrough_lines = passthrough_lines
  )
}

fn_source <- function(parsed) {
  lines <- parsed$lines
  start <- parsed$fn_start
  depth <- 0; started <- FALSE; end <- start
  for (i in start:length(lines)) {
    opens  <- lengths(regmatches(lines[i], gregexpr("\\{", lines[i])))
    closes <- lengths(regmatches(lines[i], gregexpr("\\}", lines[i])))
    if (opens > 0) started <- TRUE
    depth <- depth + opens - closes
    if (started && depth <= 0) { end <- i; break }
    end <- i
  }
  paste(lines[start:end], collapse = "\n")
}

# --- Profile selection ---------------------------------------------------

select_profile <- function(parsed) {
  if (parsed$is_exported) style$exported else style$internal
}

build_guidance_text <- function(profile) {
  parts <- vapply(names(profile), function(tag) sprintf("- %s: %s", tag, profile[[tag]]$guidance), character(1))
  paste(parts, collapse = "\n")
}

# --- DataSHIELD demo environment: multi-study login snippet ---------------

build_demo_login_snippet <- function(package_name, group, server) {
  appends <- vapply(group$studies, function(s) {
    sprintf(
      paste(
        "builder$append(server = \"%s\",",
        "               url = \"%s\",",
        "               user = \"%s\", password = \"%s\",",
        "               table = \"%s\", driver = \"%s\")",
        sep = "\n"
      ),
      s$server_label, server$url, server$user, server$password, s$table, server$driver
    )
  }, character(1))

  paste(
    "require('DSI')",
    "require('DSOpal')",
    sprintf("require('%s')", package_name),
    "",
    "builder <- DSI::newDSLoginBuilder()",
    paste(appends, collapse = "\n"),
    "logindata <- builder$build()",
    "connections <- DSI::datashield.login(logins = logindata, assign = TRUE, symbol = \"D\")",
    "",
    "# ... call the function being documented here ...",
    "",
    "datashield.logout(connections)",
    sep = "\n"
  )
}

# --- DataSHIELD role-specific guidance ------------------------------------

role_guidance <- function(datashield, ds_type, matched_group, example_env) {
  if (!isTRUE(datashield)) return("")

  if (identical(ds_type, "client")) {
    text <- paste(
      "This function is part of a DataSHIELD CLIENT-side package. Client-side",
      "functions typically construct and dispatch a call to a DataSHIELD server",
      "(e.g. via DSI::datashield.aggregate() or .assign()) rather than performing",
      "computation locally. When documenting:",
      "- param docs: note where a parameter names an object that exists on the",
      "  server (e.g. a table or variable name), rather than a local R value,",
      "  if that is the case.",
      "- return doc: describe what is actually returned to the caller in R",
      "  (which may be a status, a message, or a lightweight object), not",
      "  results that are computed server-side and never returned by this",
      "  function.",
      "- details: focus on what server-side call this function constructs. If",
      "  the function's code identifies a specific server-side function it",
      "  invokes (e.g. a function name passed as a string or symbol to a call",
      "  construction), name it explicitly using the established convention:",
      "  'Server function called: the name in code font'. Only include this",
      "  if a specific name is actually identifiable from the code; never",
      "  guess or fabricate one.",
      "If a corresponding server-side function or package exists, you may note",
      "the relationship briefly — but do not assume or invent one; some client",
      "packages are standalone wrappers with no server-side counterpart.",
      sep = "\n"
    )
    if (!is.null(matched_group)) {
      demo_snippet <- build_demo_login_snippet(package_name, matched_group, example_env$server)
      demo_text <- paste(
        "",
        "Canonical current demo environment for the examples field — use this",
        "verbatim as the example code (do not add any comment markers, tag",
        "labels, or wrapper syntax yourself — the script adds that structure).",
        "This reflects DataSHIELD's typical multi-centric usage (multiple",
        "studies connected at once). Treat any existing example content that",
        "connects to only one server, or references a different server or VM",
        "setup, as outdated and replace it with this:",
        "",
        demo_snippet,
        sep = "\n"
      )
      text <- paste(text, demo_text, sep = "\n")
    }
    text
  } else if (identical(ds_type, "server")) {
    paste(
      "This function is part of a DataSHIELD SERVER-side package. Server-side",
      "functions typically perform the actual computation (often using base R,",
      "stats, or tidyverse functions directly) on data not directly visible to",
      "the client. When documenting:",
      "- param docs: parameters are typically real, resolved R objects at",
      "  this point.",
      "- return doc: describe the actual computed result, including type and",
      "  shape.",
      "- details: reference the base/stats/tidyverse functions this builds on",
      "  where it aids understanding.",
      sep = "\n"
    )
  } else {
    ""
  }
}

# --- Build the Claude tool schema (flat, one level per step) --------------

build_submit_review_tool <- function(parsed) {
  param_properties <- setNames(
    lapply(parsed$params, function(p) {
      list(type = "string", description = sprintf("Documentation prose for parameter '%s'.", p))
    }),
    parsed$params
  )

  params_schema <- list(
    type = "object",
    description = "One entry per function parameter, keyed by exact parameter name.",
    properties = param_properties,
    required = as.list(parsed$params)
  )

  top_level_properties <- list(
    needs_changes = list(type = "boolean", description = "Whether any field needs to change."),
    changed_tags = list(type = "array", items = list(type = "string"), description = "Names of fields actually changed."),
    title = list(type = "string", description = "Plain-text title, no markup, matching the style guidance."),
    description = list(type = "string", description = "Plain-text description prose."),
    details = list(type = "string", description = "Plain-text details prose. Empty string if not applicable."),
    return_doc = list(type = "string", description = "Plain-text description of the return value."),
    examples_body = list(type = "string", description = "Raw runnable example code only, no comment markers, no tag label, no wrapper syntax. Empty string if examples are not required and none exist."),
    params = params_schema
  )

  input_schema <- list(
    type = "object",
    properties = top_level_properties,
    required = list("needs_changes", "changed_tags", "title", "description", "return_doc", "params")
  )

  list(
    name = "submit_review",
    description = "Submit the roxygen2 documentation review as individual prose fields, never as assembled roxygen text.",
    input_schema = input_schema
  )
}

# --- Ask Claude for structured PROSE FIELDS ONLY — never assembled text ---

ask_claude <- function(parsed, profile, role_text) {
  existing_block <- if (length(parsed$roxygen_lines) > 0) {
    paste(parsed$roxygen_lines, collapse = "\n")
  } else {
    "(none — no roxygen block exists for this function yet)"
  }

  param_list <- if (length(parsed$params) > 0) paste(parsed$params, collapse = ", ") else "(none)"

  prompt <- sprintf(paste(
    "You are reviewing roxygen2 documentation for an R function for accuracy",
    "and completeness. You do NOT write roxygen syntax, comment markers, or",
    "tag labels — you only supply the prose content for each field below. A",
    "script assembles the final documentation from your fields, so there is",
    "no way for you to duplicate anything or get the tag order wrong; just",
    "answer each field once.",
    "",
    "Style requirements per field:",
    "%s",
    "",
    "%s",
    "",
    "Existing roxygen block (for context on current wording/accuracy only —",
    "DO NOT COPY OR ECHO THIS BACK. If any field in your answer contains",
    "text from this block — including its comment markers (#') or tag",
    "labels like @param, @return, @export, @import — that is an error. Every",
    "field must be your own new prose, written from scratch, with no",
    "roxygen syntax of any kind:",
    "%s",
    "",
    "Function source:",
    "%s",
    "",
    "Function parameters, in order: %s",
    "",
    "For each field: if existing content is already accurate and meets the",
    "guidance, return that same content essentially unchanged (do not reword",
    "something already correct). Treat placeholder or lazy content (e.g.",
    "\"XXXXX\", \"TODO\", \"tbd\") and stale content (e.g. an outdated example",
    "server) as inadequate and rewrite it. List every field you actually",
    "changed in changed_tags.",
    "",
    "Do not include export or import directives anywhere in your answer —",
    "those are handled entirely outside this review and are not part of any",
    "field.",
    "",
    "Call the submit_review tool with your result. Do not write any prose",
    "response — only call the tool.",
    sep = "\n"
  ), build_guidance_text(profile), role_text, existing_block, fn_source(parsed), param_list)

  submit_review_tool <- build_submit_review_tool(parsed)

  req <- request("https://api.anthropic.com/v1/messages") |>
    req_headers(
      "Authorization" = paste("Bearer", api_key),
      "anthropic-version" = "2023-06-01",
      "content-type" = "application/json"
    ) |>
    req_body_json(list(
      model = "claude-sonnet-5",
      max_tokens = 4096,
      thinking = list(type = "disabled"),
      tools = list(submit_review_tool),
      tool_choice = list(type = "tool", name = "submit_review"),
      messages = list(list(role = "user", content = prompt))
    )) |>
    req_error(is_error = function(resp) FALSE)  # handle errors manually so we can see the real body

  resp <- req_perform(req)

  if (resp_status(resp) >= 400) {
    stop(sprintf(
      "Anthropic API error (HTTP %d): %s",
      resp_status(resp), resp_body_string(resp)
    ))
  }

  body <- resp_body_json(resp)

  tool_block <- Filter(function(block) identical(block$type, "tool_use"), body$content)
  if (length(tool_block) == 0) {
    stop(sprintf(
      "No tool_use content block in Claude's response. Full response: %s",
      jsonlite::toJSON(body, auto_unbox = TRUE)
    ))
  }

  tool_block[[1]]$input
}

# --- Deterministic assembly: the ONLY place the final block is built -----
# Defense in depth: strip any roxygen syntax (comment markers, tag labels)
# that leaks into a Claude-supplied field before it's ever wrapped. This
# guards against the model echoing the "existing roxygen block" context
# back into a field instead of writing new prose, which no amount of
# prompt wording alone has reliably prevented.

sanitize_field <- function(text, field_name, path) {
  if (is.null(text) || !nzchar(trimws(text))) return(text %||% "")
  lines <- strsplit(text, "\n")[[1]]
  is_artifact <- grepl("^\\s*#'", lines) | grepl("^\\s*@[A-Za-z]+\\b", lines)
  if (any(is_artifact)) {
    message(sprintf(
      "%s: field '%s' contained roxygen syntax (comment markers or tag labels) — stripping before assembly. This indicates Claude echoed context instead of writing new prose.",
      path, field_name
    ))
    lines <- lines[!is_artifact]
  }
  paste(lines, collapse = "\n")
}

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
      sections[["title"]] <- c(wrap(title), "#'")
    } else if (tag == "description") {
      sections[["description"]] <- c(wrap(description), "#'")
    } else if (tag == "details" && nzchar(trimws(details))) {
      sections[["details"]] <- c(wrap(paste0("@details ", details)), "#'")
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

# --- Mode-specific output --------------------------------------------------

write_in_place <- function(path, parsed, new_block) {
  lines <- parsed$lines
  new_lines <- strsplit(new_block, "\n")[[1]]
  before <- if (parsed$pre_end >= 1) lines[seq_len(parsed$pre_end)] else character(0)
  after  <- lines[seq(parsed$fn_start, length(lines))]
  writeLines(c(before, new_lines, parsed$gap_lines, after), path)
}

post_suggestion_comment <- function(path, parsed, new_block, changed_tags) {
  intro <- if (length(changed_tags) > 0) {
    sprintf("Updated: %s\n\n", paste(unlist(changed_tags), collapse = ", "))
  } else ""

  if (parsed$has_roxygen) {
    start_line <- parsed$roxygen_start
    end_line   <- parsed$roxygen_end
    body <- paste0(intro, "```suggestion\n", new_block, "\n```")
  } else {
    start_line <- parsed$fn_start
    end_line   <- parsed$fn_start
    body <- paste0(
      intro, "```suggestion\n", new_block, "\n", parsed$fn_header, "\n```"
    )
  }

  req <- request(sprintf("https://api.github.com/repos/%s/pulls/%s/comments", repo, pr_number)) |>
    req_headers("Authorization" = paste("Bearer", gh_token), "Accept" = "application/vnd.github+json") |>
    req_body_json(list(
      body = body, commit_id = pr_head_sha, path = path,
      start_line = start_line, line = end_line, side = "RIGHT", start_side = "RIGHT"
    ))

  tryCatch(req_perform(req), error = function(e) {
    message(sprintf("Failed to post suggestion comment for %s: %s", path, conditionMessage(e)))
  })
}

# --- Main loop ---------------------------------------------------------------

for (f in files) {
  parsed <- tryCatch(parse_r_file(f), error = function(e) {
    message(sprintf("Skipping %s: %s", f, conditionMessage(e)))
    NULL
  })
  if (is.null(parsed)) next

  profile   <- select_profile(parsed)
  role_text <- role_guidance(datashield, ds_type, matched_group, example_env)

  result <- tryCatch(ask_claude(parsed, profile, role_text), error = function(e) {
    message(sprintf("Claude call failed for %s: %s", f, conditionMessage(e)))
    NULL
  })
  if (is.null(result)) next

  if (!isTRUE(result$needs_changes)) {
    message(sprintf("%s: documentation already adequate, skipping.", f))
    next
  }

  new_block <- tryCatch(build_roxygen_block(result, parsed, f), error = function(e) {
    message(sprintf("Failed to assemble roxygen block for %s: %s", f, conditionMessage(e)))
    NULL
  })
  if (is.null(new_block)) next

  message(sprintf("%s: updating %s.", f, paste(unlist(result$changed_tags), collapse = ", ")))

  if (identical(scan_mode, "all")) {
    write_in_place(f, parsed, new_block)
  } else {
    post_suggestion_comment(f, parsed, new_block, result$changed_tags)
  }
}
