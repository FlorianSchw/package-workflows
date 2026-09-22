# Shared low-level Claude tool-call mechanics: builds the request, forces
# the given tool, and returns its parsed input. Every Claude-calling
# function (roxygen's review, test generation, failure classification —
# and whatever comes after) shares this exact request/error-handling/
# tool-extraction logic; before this existed it was duplicated verbatim in
# each one. Only the config, tool schema, and prompt differ per caller.
call_claude_tool <- function(config, tool, prompt) {
  req <- request("https://api.anthropic.com/v1/messages") |>
    req_headers(
      "Authorization" = paste("Bearer", api_key),
      "anthropic-version" = config$api_version,
      "content-type" = "application/json"
    ) |>
    req_body_json(list(
      model = config$model,
      max_tokens = config$max_tokens,
      thinking = config$thinking,
      tools = list(tool),
      tool_choice = list(type = config$tool_choice_type, name = config$tool_name),
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
