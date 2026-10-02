# Sends the roxygen review request to Claude and returns the submit_review
# tool call's input — individual prose fields only, never assembled roxygen
# text. `earlier` are this bot's open earlier findings on the function
# (from its open suggestion PR), to be judged and not repeated. Without
# `with_code_issues` (code-issue-confidence "none"), possible bugs aren't
# asked for.
ask_claude_for_review <- function(parsed, profile, role_text, earlier = list(), with_code_issues = TRUE) {
  existing_block <- if (length(parsed$roxygen_lines) > 0) {
    paste(parsed$roxygen_lines, collapse = "\n")
  } else {
    "(none — no roxygen block exists for this function yet)"
  }

  prompt <- fill_template(roxygen_review_prompt_template, list(
    STYLE_GUIDANCE   = build_guidance_text(profile),
    ROLE_GUIDANCE    = role_text,
    EXISTING_BLOCK   = existing_block,
    FUNCTION_SOURCE  = fn_source(parsed),
    PARAMS           = if (length(parsed$params) > 0) paste(parsed$params, collapse = ", ") else "(none)",
    EARLIER_FINDINGS = format_earlier_findings(earlier)
  ))

  call_claude_tool(anthropic_config, build_submit_review_tool(parsed, profile, earlier, with_code_issues), prompt)
}
