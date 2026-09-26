# Checks Claude's decisions on existing tests against the safeguards
# before anything is applied (see dev-notes/suggestion-thresholds.md):
# - action and reason must fit together: update <- contract_changed,
#   delete <- duplicate / behavior_removed / trivial,
#   report <- possible_code_bug;
# - the test must exist and be editable (parse_test_file());
# - only a test that currently FAILS is updated — a passing test is never
#   rewritten, and a test that fails because of a possible bug is only
#   reported, never adapted to the code's current output.
# Returns proposed `updates` (description -> assembled test_that() text),
# `deletes`, their `explanations`, and report `notes`. Updates still have
# to pass a real run before they are kept.
review_existing_tests <- function(decisions, blocks, baseline, function_name) {
  fits <- list(update = "contract_changed", delete = c("duplicate", "behavior_removed", "trivial"), report = "possible_code_bug")
  failing <- vapply(Filter(function(r) !isTRUE(r$passed), baseline), function(r) r$description, character(1))
  label <- function(d) sprintf("\"%s\"", d$description)

  out <- list(updates = character(0), deletes = character(0), explanations = character(0), notes = character(0))
  for (d in decisions) {
    block <- Find(function(b) identical(b$description, d$description), blocks)
    if (is.null(block)) {
      message(sprintf("%s: ignoring decision on '%s' — no such test.", function_name, d$description))
      next
    }
    if (!isTRUE(d$reason %in% fits[[d$action]])) {
      message(sprintf("%s: ignoring %s of '%s' — reason '%s' doesn't fit.", function_name, d$action, d$description, d$reason))
      next
    }
    if (d$action == "report") {
      out$notes <- c(out$notes, sprintf("- %s — possible bug in the code, test left unchanged. %s", label(d), d$explanation))
      next
    }
    if (!block$editable) {
      out$notes <- c(out$notes, sprintf("- %s — suggested %s (`%s`), but the test can't be edited automatically (duplicate name or shared lines). %s", label(d), d$action, d$reason, d$explanation))
      next
    }
    if (d$action == "update") {
      if (!d$description %in% failing) {
        message(sprintf("%s: not updating '%s' — it currently passes.", function_name, d$description))
        next
      }
      assembled <- tryCatch(
        assemble_test_block(list(list(description = d$description, setup_code = d$setup_code, assertions_code = d$assertions_code)), function_name),
        error = function(e) {
          message(sprintf("%s: could not assemble update of '%s': %s", function_name, d$description, conditionMessage(e)))
          NULL
        }
      )
      if (is.null(assembled)) next
      out$updates[d$description] <- assembled[[1]]
    } else {
      out$deletes <- c(out$deletes, d$description)
    }
    out$explanations[d$description] <- sprintf("%s (`%s`): %s", if (d$action == "update") "updated" else "deleted", d$reason, d$explanation)
  }
  out
}
