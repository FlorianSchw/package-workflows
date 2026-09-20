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

source(load_config("scripts/parse_r_file.R", ".shared-workflows/scripts/parse_r_file.R"))

style <- fromJSON(
  load_config("roxygen-style.json", ".shared-workflows/config/roxygen-style.json"),
  simplifyVector = FALSE
)

prompt_template <- paste(
  readLines(
    load_config("prompts/roxygen-review-prompt.md", ".shared-workflows/prompts/roxygen-review-prompt.md"),
    warn = FALSE
  ),
  collapse = "\n"
)

example_env <- NULL
if (isTRUE(datashield) && identical(ds_type, "client")) {
  env_path <- load_config("datashield-example-env.json", ".shared-workflows/config/datashield-example-env.json")
  if (file.exists(env_path)) example_env <- fromJSON(env_path, simplifyVector = FALSE)
}

role_guidance_config <- NULL
if (isTRUE(datashield)) {
  role_guidance_path <- load_config("datashield-role-guidance.json", ".shared-workflows/config/datashield-role-guidance.json")
  if (file.exists(role_guidance_path)) role_guidance_config <- fromJSON(role_guidance_path, simplifyVector = FALSE)
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

build_role_guidance_text <- function(cfg) {
  if (is.null(cfg)) return("")
  join <- function(x) paste(unlist(x), collapse = " ")
  doc <- cfg$documentation
  parts <- c(
    join(cfg$intro),
    sprintf("- param docs: %s", join(doc$param)),
    sprintf("- return doc: %s", join(doc$return)),
    sprintf("- details: %s", join(doc$details))
  )
  if (!is.null(cfg$closing) && length(cfg$closing) > 0) {
    parts <- c(parts, join(cfg$closing))
  }
  paste(parts, collapse = "\n")
}

role_guidance <- function(datashield, ds_type, matched_group, example_env, role_guidance_config) {
  if (!isTRUE(datashield)) return("")

  if (identical(ds_type, "client")) {
    text <- build_role_guidance_text(role_guidance_config$client)
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
    build_role_guidance_text(role_guidance_config$server)
  } else {
    ""
  }
}

# --- Build the Claude tool schema (flat, one level per step) --------------

build_submit_review_tool <- function(parsed, profile) {
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
    title = list(type = "string", description = sprintf("Plain-text title, no markup. %s", profile$title$guidance)),
    description = list(type = "string", description = sprintf("Plain-text description prose. %s", profile$description$guidance)),
    details = list(type = "string", description = sprintf("Plain-text details prose, empty string if not applicable. %s", profile$details$guidance)),
    return_doc = list(type = "string", description = sprintf("Plain-text description of the return value. %s", profile$return$guidance)),
    examples_body = list(type = "string", description = sprintf("Raw runnable example code only, no comment markers, no tag label, no wrapper syntax, empty string if not required. %s", profile$examples$guidance)),
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

  prompt <- prompt_template
  prompt <- gsub("{{STYLE_GUIDANCE}}", build_guidance_text(profile), prompt, fixed = TRUE)
  prompt <- gsub("{{ROLE_GUIDANCE}}", role_text, prompt, fixed = TRUE)
  prompt <- gsub("{{EXISTING_BLOCK}}", existing_block, prompt, fixed = TRUE)
  prompt <- gsub("{{FUNCTION_SOURCE}}", fn_source(parsed), prompt, fixed = TRUE)
  prompt <- gsub("{{PARAMS}}", param_list, prompt, fixed = TRUE)

  submit_review_tool <- build_submit_review_tool(parsed, profile)

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
  role_text <- role_guidance(datashield, ds_type, matched_group, example_env, role_guidance_config)

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
