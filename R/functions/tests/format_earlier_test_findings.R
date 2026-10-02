# This bot's open earlier findings on a function, from its open suggestion
# PR, for the prompt: existing tests it reported (possible bugs, failing
# tests left unchanged) and generated tests that failed — each with the id
# Claude uses to mark repeats and judge them (build_submit_tests_tool()).
# New, updated and deleted tests aren't listed: they are part of the test
# files Claude sees (materialize_bot_tests()).
format_earlier_test_findings <- function(earlier) {
  if (length(earlier) == 0) return("(none)")
  lines <- vapply(earlier, function(e) {
    if (identical(e$kind, "failed")) {
      sprintf("- E%d — a generated test that failed (`%s`), not proposed: \"%s\". %s", e$id, e$classification, e$description, e$explanation)
    } else {
      sprintf("- E%d — reported existing test \"%s\" in `%s`: %s", e$id, e$description, basename(e$file), e$explanation)
    }
  }, character(1))
  paste(lines, collapse = "\n")
}
