# The triggers in the order the diagrams use them — the one that says most
# about a workflow's role first: pull requests, pushes, releases, chains
# from other workflows, calls, schedules, manual runs. Decides a
# workflow's main trigger (main_trigger()) and the order of the overview's
# lanes.
trigger_order <- function() {
  c("pull_request", "pull_request_target", "push", "release", "workflow_run",
    "repository_dispatch", "workflow_call", "schedule", "workflow_dispatch")
}
