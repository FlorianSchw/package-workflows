# Sends the script request to Claude and returns the tool call's steps.
# `context` holds what every request shares: the prompt template
# (prompts/analysis-script-prompt.md), plan text, symbol, connections,
# servers, function reference, catalogue text, package and function
# names, open gap issues, existing steps, line limit and file number per
# step. `step_ids` are the steps to write; `previous_attempt` is empty on
# the first call and, in a repair round,
# describes the failed attempt (code and errors) for those steps.
ask_claude_for_scripts <- function(context, step_ids, previous_attempt = "") {
  prompt <- fill_template(context$prompt_template, list(
    CONNECTIONS        = context$connections,
    SYMBOL             = context$symbol,
    SERVERS            = paste(sprintf("`%s`", context$servers), collapse = ", "),
    FUNCTION_REFERENCE = context$function_reference,
    CATALOGUE          = context$catalogue_text,
    GAP_ISSUES         = if (nrow(context$gap_issues) == 0) "(none)" else paste(sprintf("- #%s: %s", context$gap_issues$number, context$gap_issues$title), collapse = "\n"),
    EXISTING_STEPS     = context$existing_steps,
    PLAN               = context$plan_text,
    REQUESTED_STEPS    = paste(sprintf("`%s` (%s)", step_ids, unlist(context$numbers[step_ids])), collapse = ", "),
    MAX_LINES          = as.character(context$max_lines),
    PREVIOUS_ATTEMPT   = previous_attempt
  ))
  tool <- build_analysis_tool(step_ids, context$catalogue_names, context$catalogue_functions, context$gap_issues$number)
  result <- call_claude_tool(anthropic_config, tool, prompt)
  Filter(function(s) s$step_id %in% step_ids, result$steps)
}
