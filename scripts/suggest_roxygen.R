#!/usr/bin/env Rscript
# Reads files_to_check.txt (produced by the calling workflow), reviews each
# function's roxygen2 documentation for completeness AND accuracy against
# style guidance (and, for DataSHIELD packages, role-specific guidance), and
# either posts a GitHub PR suggestion comment (SCAN_MODE=changed) or rewrites
# the file in place (SCAN_MODE=all, caller commits + opens a PR).

library(httr2)
library(jsonlite)

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
  params <- trimws(vapply(split_args(args_str), function(a) sub("=.*$", "", a), character(1)))
  params <- params[nzchar(params)]

  rox_end <- fn_start - 1
  rox_start <- rox_end
  while (rox_start >= 1 && grepl("^\\s*#'", lines[rox_start])) rox_start <- rox_start - 1
  rox_start <- rox_start + 1
  has_roxygen <- rox_start <= rox_end
  roxygen_lines <- if (has_roxygen) lines[rox_start:rox_end] else character(0)

  list(
    lines = lines, fn_start = fn_start, fn_header = header_text, params = params,
    roxygen_start = if (has_roxygen) rox_start else fn_start,
    roxygen_end = if (has_roxygen) rox_end else fn_start - 1,
    roxygen_lines = roxygen_lines
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

select_profile <- function(parsed, style) {
  body <- if (length(parsed$roxygen_lines) > 0) sub("^\\s*#'\\s?", "", parsed$roxygen_lines) else character(0)
  is_exported <- any(grepl("^@export\\b", body))
  if (is_exported) style$exported else style$internal
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
        "  builder$append(server = \"%s\",",
        "                 url = \"%s\",",
        "                 user = \"%s\", password = \"%s\",",
        "                 table = \"%s\", driver = \"%s\")",
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
      "- @param: note where a parameter names an object that exists on the",
      "  server (e.g. a table or variable name), rather than a local R value,",
      "  if that is the case.",
      "- @return: describe what is actually returned to the caller in R (which",
      "  may be a status, a message, or a lightweight object), not results",
      "  that are computed server-side and never returned by this function.",
      "- @details: focus on what server-side call this function constructs. If",
      "  the function's code identifies a specific server-side function it",
      "  invokes (e.g. a function name passed as a string or symbol to a call",
      "  construction), name it explicitly on its own line in the established",
      "  convention: 'Server function called: \\code{<name>}'. Only include",
      "  this if a specific name is actually identifiable from the code; never",
      "  guess or fabricate one.",
      "If a corresponding server-side function or package exists, you may note",
      "the relationship briefly — but do not assume or invent one; some client",
      "packages are standalone wrappers with no server-side counterpart.",
      sep = "\n"
    )
    if (!is.null(matched_group)) {
      text <- paste(text, sprintf(paste(
        "",
        "Canonical current demo environment for @examples — use this verbatim",
        "when drafting or replacing an example block. This reflects DataSHIELD's",
        "typical multi-centric usage (multiple studies connected at once), not",
        "a single-server setup. Treat any existing @examples content that",
        "connects to only one server, or references a different server, VM",
        "setup, or connection pattern, as OUTDATED and replace it with this:",
        "",
        "%s",
        sep = "\n"
      ), build_demo_login_snippet(package_name, matched_group, example_env$server)))
    }
    text
  } else if (identical(ds_type, "server")) {
    paste(
      "This function is part of a DataSHIELD SERVER-side package. Server-side",
      "functions typically perform the actual computation (often using base R,",
      "stats, or tidyverse functions directly) on data not directly visible to",
      "the client. When documenting:",
      "- @param: parameters are typically real, resolved R objects at this point.",
      "- @return: describe the actual computed result, including type and shape.",
      "- @details: reference the base/stats/tidyverse functions this builds on",
      "  where it aids understanding.",
      sep = "\n"
    )
  } else {
    ""
  }
}

# --- Ask Claude to REVIEW, not just fill gaps -----------------------------

ask_claude <- function(parsed, profile, role_text) {
  existing_block <- if (length(parsed$roxygen_lines) > 0) {
    paste(parsed$roxygen_lines, collapse = "\n")
  } else {
    "(none — no roxygen block exists for this function yet)"
  }

  prompt <- sprintf(paste(
    "You are reviewing roxygen2 documentation for an R function for accuracy",
    "and completeness — not rewriting it wholesale.",
    "",
    "Style requirements per tag:",
    "%s",
    "",
    "%s",
    "",
    "Existing roxygen block:",
    "%s",
    "",
    "Function source:",
    "%s",
    "",
    "For EACH required tag: judge whether the existing content (if present)",
    "is accurate, complete, and meets the guidance above. Treat placeholder",
    "or lazy content (e.g. \"XXXXX\", \"TODO\", \"tbd\", or text that doesn't",
    "actually describe the real parameter/return value) as inadequate, not",
    "as present. Treat stale content (a description, or an @examples server",
    "setup, that no longer matches reality) as inadequate too.",
    "",
    "Only regenerate tags that are missing, inaccurate, or inadequate. Copy",
    "every already-adequate tag through byte-for-byte unchanged — do not",
    "reword or 'improve' something that already meets the guidance, even if",
    "you would have phrased it differently.",
    "",
    "Return ONLY a JSON object:",
    "{",
    "  \"needs_changes\": true or false,",
    "  \"changed_tags\": [\"list\", \"of\", \"tags you actually changed\"],",
    "  \"roxygen_block\": \"complete replacement block if needs_changes is true, else omit\"",
    "}",
    "If every required tag is already adequate, return needs_changes: false",
    "and omit roxygen_block. Do not produce a suggestion just to make small",
    "stylistic tweaks to content that already meets the guidance.",
    sep = "\n"
  ), build_guidance_text(profile), role_text, existing_block, fn_source(parsed))

  resp <- request("https://api.anthropic.com/v1/messages") |>
    req_headers(
      "Authorization" = paste("Bearer", api_key),
      "anthropic-version" = "2023-06-01",
      "content-type" = "application/json"
    ) |>
    req_body_json(list(
      model = "claude-sonnet-5",
      max_tokens = 1024,
      messages = list(list(role = "user", content = prompt))
    )) |>
    req_perform()

  body <- resp_body_json(resp)

  text_block <- Filter(function(block) identical(block$type, "text"), body$content)
  if (length(text_block) == 0) {
    stop(sprintf(
      "No text content block in Claude's response. Full response: %s",
      jsonlite::toJSON(body, auto_unbox = TRUE)
    ))
  }

  fromJSON(text_block[[1]]$text, simplifyVector = FALSE)
}

# --- Mode-specific output --------------------------------------------------

write_in_place <- function(path, parsed, new_block) {
  lines <- parsed$lines
  new_lines <- strsplit(new_block, "\n")[[1]]
  before <- if (parsed$roxygen_start > 1) lines[seq_len(parsed$roxygen_start - 1)] else character(0)
  after  <- lines[seq(parsed$fn_start, length(lines))]
  writeLines(c(before, new_lines, after), path)
}

post_suggestion_comment <- function(path, parsed, new_block, changed_tags) {
  start_line <- parsed$roxygen_start
  end_line   <- parsed$fn_start - 1
  if (end_line < start_line) end_line <- start_line

  intro <- if (length(changed_tags) > 0) {
    sprintf("Updated: %s\n\n", paste(unlist(changed_tags), collapse = ", "))
  } else ""

  body <- paste0(intro, "```suggestion\n", new_block, "\n```")

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

  profile   <- select_profile(parsed, style)
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

  message(sprintf("%s: updating %s.", f, paste(unlist(result$changed_tags), collapse = ", ")))

  if (identical(scan_mode, "all")) {
    write_in_place(f, parsed, result$roxygen_block)
  } else {
    post_suggestion_comment(f, parsed, result$roxygen_block, result$changed_tags)
  }
}
