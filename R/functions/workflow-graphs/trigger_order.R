# The triggers in the order the diagrams and the table use them: pull
# requests, pushes, releases, chains from other workflows, calls,
# schedules, manual runs. Decides the order of the overview's situations
# (workflow_situations()) and of the triggers in the table
# (workflow_summary_table()).
trigger_order <- function() {
  c("pull_request", "pull_request_target", "push", "release", "workflow_run",
    "repository_dispatch", "workflow_call", "schedule", "workflow_dispatch")
}
