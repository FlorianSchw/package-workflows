# Shared low-level Claude tool-call mechanics: builds the request, forces
# the given tool, and returns its parsed input. Every Claude-calling
# function shares this; only the config profile, tool schema, and prompt
# differ per caller. The tool's name is set here from config$tool_name —
# the same value tool_choice forces — so the two can never disagree; tool
# schema builders deliberately leave `name` out.
#
# Optional per profile in config/claude.yml: `effort` (sent as
# output_config.effort), and `fallbacks` + `betas` (server-side fallback
# to another model when the request is refused).
call_claude_tool <- function(config, tool, prompt) {
  tool$name <- config$tool_name

  body <- list(
    model = config$model,
    max_tokens = config$max_tokens,
    thinking = config$thinking,
    tools = list(tool),
    tool_choice = list(type = config$tool_choice_type, name = config$tool_name),
    messages = list(list(role = "user", content = prompt))
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
    req_error(is_error = function(resp) FALSE)  # handle errors manually so we can see the real body
  if (!is.null(config$betas)) req <- req_headers(req, "anthropic-beta" = paste(unlist(config$betas), collapse = ","))

  resp <- req_perform(req)

  if (resp_status(resp) >= 400) {
    stop(sprintf(
      "Anthropic API error (HTTP %d): %s",
      resp_status(resp), resp_body_string(resp)
    ))
  }

  body <- resp_body_json(resp)

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
