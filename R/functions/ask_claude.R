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

  call_claude_tool(anthropic_config, submit_review_tool, prompt)
}
