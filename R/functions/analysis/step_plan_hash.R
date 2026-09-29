# Hash of what a step was generated from: the step's own plan entry plus
# the plan's core (symbol, studies, variables). A step is regenerated when
# this changes and its files are untouched.
step_plan_hash <- function(plan, step) {
  text_hash(yaml::as.yaml(list(core = plan[c("symbol", "studies", "variables")], step = step)))
}
