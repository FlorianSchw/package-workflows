# Pieces of the test bot that run code or touch the package: generated
# tests without credentials, packages added to Suggests, the summary line,
# and fetching the bot branch.

local_mini_package <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  dir.create(file.path(dir, "R"))
  dir.create(file.path(dir, "tests", "testthat"), recursive = TRUE)
  writeLines(c("Package: minipkg", "Version: 0.1", "Title: t", "Description: t.", "License: MIT",
               "Imports: jsonlite", "Suggests: testthat (>= 3.0.0)"), file.path(dir, "DESCRIPTION"))
  writeLines("export(add1)", file.path(dir, "NAMESPACE"))
  writeLines("add1 <- function(x) x + 1", file.path(dir, "R", "add1.R"))
  dir
}

test_that("run_test_blocks() runs tests in a separate process without credentials", {
  dir <- local_mini_package()
  writeLines(c(
    'test_that("adds one", { expect_equal(add1(1), 2) })',
    'test_that("sees no token", { expect_equal(Sys.getenv("ANTHROPIC_API_KEY"), ""); expect_equal(Sys.getenv("GH_TOKEN"), "") })',
    'test_that("fails on purpose", { expect_equal(add1(1), 3) })',
    'leaked <- TRUE'
  ), file.path(dir, "tests", "testthat", "test-add1.R"))
  withr::local_dir(dir)
  withr::local_envvar(ANTHROPIC_API_KEY = "secret", GH_TOKEN = "ghs_secret")
  res <- run_test_blocks("tests/testthat/test-add1.R", "minipkg")
  expect_equal(vapply(res, function(r) r$passed, logical(1)), c(TRUE, TRUE, FALSE))
  expect_match(res[[3]]$message, "3")
  expect_false(exists("leaked", envir = globalenv()))
  expect_equal(Sys.getenv("ANTHROPIC_API_KEY"), "secret")  # the bot keeps its own
})

test_that("declare_test_packages() adds undeclared packages to Suggests, once", {
  dir <- local_mini_package()
  writeLines(c('test_that("a", {', '  d <- withr::local_tempdir()', '  library(mockery)',
               '  requireNamespace("digest", quietly = TRUE)', '  stats::sd(1:2); jsonlite::toJSON(1); minipkg::add1(1)', '})'),
             file.path(dir, "tests", "testthat", "test-a.R"))
  withr::local_dir(dir)
  expect_setequal(declare_test_packages("minipkg", "tests/testthat/test-a.R"), c("withr", "mockery", "digest"))
  expect_length(declare_test_packages("minipkg", "tests/testthat/test-a.R"), 0)
  state <- merge_test_findings(list(entries = list(), next_id = 1L), "", list(dependencies = c("withr")), sha = "abc")$state
  expect_match(format_test_summary(state), "added to Suggests: `withr`")
})

test_that("fetch_bot_branch() fetches without a token, and builds a one-line header with one", {
  dir <- withr::local_tempdir()
  bare <- file.path(dir, "remote.git")
  git <- function(...) system2("git", c(...), stdout = FALSE, stderr = FALSE)
  git("init", "-q", "--bare", shQuote(bare))
  git("clone", "-q", shQuote(bare), shQuote(file.path(dir, "work")))
  withr::local_dir(file.path(dir, "work"))
  writeLines("x", "f.txt")
  git("add", "f.txt")
  git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "c")
  git("push", "-q", "origin", "HEAD:refs/heads/bot-suggest/tests/dev")
  withr::local_envvar(GH_TOKEN = "")
  expect_equal(fetch_bot_branch("bot-suggest/tests/dev"), "refs/remotes/origin/bot-suggest/tests/dev")
  withr::local_envvar(GH_TOKEN = strrep("a", 93))  # a local remote ignores the header
  expect_equal(fetch_bot_branch("bot-suggest/tests/dev"), "refs/remotes/origin/bot-suggest/tests/dev")
})

test_that("obvious_failure_classification() decides parse errors, missing functions and packages", {
  expect_equal(obvious_failure_classification("<text>:2:5: unexpected symbol")$category, "bad_test")
  expect_match(obvious_failure_classification('could not find function "ds.nothing"')$explanation, "ds.nothing")
  expect_equal(obvious_failure_classification("there is no package called 'dsX'")$category, "env_misconfiguration")
  expect_null(obvious_failure_classification("Expected `x` to equal 3."))
})

test_that("classify_failures() sends only the open failures, in one call, and maps the answers back", {
  api_key <<- "test"
  failure_classification_config <<- list(model = "claude-opus-5", max_tokens = 1000, api_version = "2023-06-01",
                                         thinking = list(type = "adaptive"), tool_name = "submit_failure_classification",
                                         tool_choice_type = "tool")
  failure_classification_prompt_template <<- paste(readLines(file.path(repo_root, "prompts", "test-failure-classification-prompt.md")), collapse = "\n")
  items <- list(list(block = "t1", message = "Expected 2, got 3"),
                list(block = "t2", message = "<text>:1:3: unexpected symbol"),
                list(block = "t3", message = "Expected TRUE"))
  calls <- 0
  prompt_text <- ""
  answer <- list(list(type = "tool_use", id = "x", name = "submit_failure_classification", input = list(failures = list(
    list(failure = "F2", explanation = "e3", category = "real_bug", confidence = "high"),
    list(failure = "F1", explanation = "e1", category = "bad_test", confidence = "medium")))))
  res <- httr2::with_mocked_responses(function(req) {
    calls <<- calls + 1
    prompt_text <<- request_body(req)$messages[[1]]$content[[1]]$text
    claude_response(answer)
  }, suppressMessages(classify_failures(items, "f <- function() 1", "f")))
  expect_equal(calls, 1)
  expect_match(prompt_text, "### F2")
  expect_false(grepl("t2", prompt_text))                # the obvious one isn't sent
  expect_equal(res[[1]]$category, "bad_test")
  expect_equal(res[[2]]$category, "bad_test")           # from R
  expect_equal(res[[3]][c("category", "confidence")], list(category = "real_bug", confidence = "high"))
})
