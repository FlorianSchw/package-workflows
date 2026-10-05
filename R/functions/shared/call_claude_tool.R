# Shared low-level Claude tool-call mechanics: builds the request, forces
# the given tool, and returns its parsed input. Every Claude-calling
# function shares this; only the config profile, tool schema, and prompt
# differ per caller. The tool's name is set here from config$tool_name —
# the same value tool_choice forces — so the two can never disagree; tool
# schema builders deliberately leave `name` out.
#
# Optional per profile in config/claude.yml: `effort` (sent as
# output_config.effort), `fallbacks` + `betas` (server-side fallback to
# another model when the request is refused), and `cache_ttl` ("5m" or
# "1h", for prompts split by split_cached_prompt()).
#
# `prompt` is a string, or list(cached, rest): the shared part then goes
# first with a cache marker, so the next call of the run with the same
# shared part (and the same tool definition, which comes before it) reads
# it from the prompt cache. Every call logs its token usage — the
# measurement channel for what a run costs (dev-notes/claude-costs.md).
call_claude_tool <- function(config, tool, prompt, renewed = FALSE) {
  tool$name <- config$tool_name

  content <- if (is.list(prompt)) {
    marker <- list(type = "ephemeral")
    if (identical(config$cache_ttl, "1h")) marker$ttl <- "1h"
    list(
      list(type = "text", text = prompt$cached, cache_control = marker),
      list(type = "text", text = prompt$rest)
    )
  } else {
    prompt
  }
  body <- list(
    model = config$model,
    max_tokens = config$max_tokens,
    thinking = config$thinking,
    tools = list(tool),
    tool_choice = list(type = config$tool_choice_type, name = config$tool_name),
    messages = list(list(role = "user", content = content))
  )
  if (!is.null(config$effort)) body$output_config <- list(effort = config$effort)
  if (!is.null(config$fallbacks)) body$fallbacks <- config$fallbacks

  req <- request("https://api.anthropic.com/v1/messages") |>
    req_headers(
      "Authorization" = paste("Bearer", api_key),
      "anthropic-version" = config$api_version,
      "content-type" = "application/json"
    ) |>
    req_body_json(body) |>
    req_timeout(900) |>
    req_error(is_error = function(resp) FALSE) |>  # handle errors manually so we can see the real body
    # Temporary failures are retried within the run: rate limit (429),
    # server errors (5xx), overloaded (529), and connection failures.
    # httr2's back-off (exponential, at most 60 s) honours Retry-After.
    req_retry(max_tries = 4,
              retry_on_failure = TRUE,
              is_transient = function(resp) resp_status(resp) %in% c(429, 500, 502, 503, 504, 529))
  if (!is.null(config$betas)) req <- req_headers(req, "anthropic-beta" = paste(unlist(config$betas), collapse = ","))

  resp <- req_perform(req)

  # The access token lives shorter than a long run: renew it once
  # (refresh_anthropic_token()) and repeat the call with the new one.
  if (resp_status(resp) == 401 && !renewed && grepl("expired", resp_body_string(resp), ignore.case = TRUE)) {
    token <- refresh_anthropic_token()
    if (!is.null(token)) {
      assign("api_key", token, envir = globalenv())
      return(call_claude_tool(config, tool, prompt, renewed = TRUE))
    }
  }

  if (resp_status(resp) >= 400) {
    # A rejected request (e.g. "JSON schema is invalid") is only explainable
    # with what was sent: log the tool definition, serialized as
    # req_body_json() sends it. Never the prompt — it can hold package code.
    if (resp_status(resp) == 400) {
      message("Tool definition sent with the rejected request:\n",
              jsonlite::toJSON(tool, auto_unbox = TRUE, digits = 22, null = "null", pretty = TRUE))
    }
    stop(sprintf(
      "Anthropic API error (HTTP %d): %s",
      resp_status(resp), resp_body_string(resp)
    ))
  }

  body <- resp_body_json(resp)
  log_claude_usage(config, body$usage)

  if (identical(body$stop_reason, "max_tokens")) {
    stop(sprintf("Claude's response was cut off at max_tokens (%s) — raise max_tokens for this profile in config/claude.yml.", config$max_tokens))
  }
  if (identical(body$stop_reason, "refusal")) {
    category <- if (is.null(body$stop_details$category)) "unknown" else body$stop_details$category
    stop(sprintf("Claude declined the request (refusal, category: %s).", category))
  }

  tool_block <- Filter(function(block) identical(block$type, "tool_use"), body$content)
  if (length(tool_block) == 0) {
    stop(sprintf(
      "No tool_use content block in Claude's response. Full response: %s",
      jsonlite::toJSON(body, auto_unbox = TRUE)
    ))
  }

  tool_block[[1]]$input
}
