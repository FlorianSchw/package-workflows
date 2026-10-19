# Self-test mode of the bot workflows (input self-test-fixture, this
# repository's own CI only): when CLAUDE_RECORDED_ANSWERS names a file of
# recorded answers (tests/fixtures/claude-answers/<fixture>.json: tool
# name -> list of tool inputs, in call order), every HTTP request of the
# run is answered locally — a Claude request with the next recorded answer
# for its tool, anything else (GitHub) with 404 — so nothing leaves the
# runner and nothing is written to GitHub. Does nothing otherwise. Called
# at the start of the entry scripts.
use_recorded_answers <- function(path = Sys.getenv("CLAUDE_RECORDED_ANSWERS"), env = globalenv()) {
  if (!nzchar(path)) return(invisible(FALSE))
  answers <- jsonlite::read_json(path)
  answers <- answers[names(answers) != "_about"]
  queue <- new.env()
  queue$answers <- answers
  mock <- function(req) {
    if (!grepl("api.anthropic.com", req$url, fixed = TRUE)) return(httr2::response(status_code = 404))
    body <- httr2::req_get_body(req)
    if (is.raw(body)) body <- rawToChar(body)
    if (is.character(body)) body <- jsonlite::fromJSON(body, simplifyVector = FALSE)
    tool <- body$tools[[1]]$name
    if (length(queue$answers[[tool]]) == 0) stop("Self-test: no recorded answer left for ", tool, call. = FALSE)
    input <- queue$answers[[tool]][[1]]
    queue$answers[[tool]] <- queue$answers[[tool]][-1]
    httr2::response(
      status_code = 200, headers = list("content-type" = "application/json"),
      body = charToRaw(jsonlite::toJSON(list(
        content = list(list(type = "tool_use", id = "toolu_self_test", name = tool, input = input)),
        stop_reason = "tool_use", usage = list(input_tokens = 0, output_tokens = 0)
      ), auto_unbox = TRUE, null = "null"))
    )
  }
  httr2::local_mocked_responses(mock, env = env)
  message("Self-test: Claude answers from ", path, "; GitHub requests answered with 404.")
  invisible(TRUE)
}
