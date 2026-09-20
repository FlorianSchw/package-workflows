# Sends the review request to Claude and returns the submit_review tool
# call's input — individual prose fields only, never assembled roxygen text.
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
      "anthropic-version" = anthropic_config$api_version,
      "content-type" = "application/json"
    ) |>
    req_body_json(list(
      model = anthropic_config$model,
      max_tokens = anthropic_config$max_tokens,
      thinking = anthropic_config$thinking,
      tools = list(submit_review_tool),
      tool_choice = list(type = anthropic_config$tool_choice_type, name = anthropic_config$tool_name),
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
