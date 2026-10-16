# Everything a Claude call of one kind needs, passed explicitly instead of
# read from global variables: the `anthropic` settings of a profile of
# config/claude.yml (model, tool name, thinking, effort, …), the prompt
# template (optional; a repository's own copy wins, resolve_shared_path()),
# and the run's access token (`auth`, claude_auth(), shared by the run's
# clients). Used by call_claude_tool() and the ask_claude_*() functions.
claude_client <- function(profile, prompt_file = NULL, auth = claude_auth()) {
  list(
    config = config::get(config = profile, file = resolve_shared_path("config/claude.yml"))$anthropic,
    prompt = if (!is.null(prompt_file)) read_text_file(prompt_file),
    auth = auth
  )
}
