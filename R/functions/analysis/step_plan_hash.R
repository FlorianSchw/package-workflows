# Hash of what a step was generated from, as the analyst wrote it: the
# step's own plan entry plus the plan's core (symbol, studies, variables).
# A step is regenerated when this changes and its files are untouched.
# The `kind` read_analysis_plan() derives from the settings is left out,
# so changing the type aliases in the settings doesn't rewrite every step.
step_plan_hash <- function(plan, step) {
  variables <- lapply(plan$variables, function(v) v[setdiff(names(v), "kind")])
  text_hash(yaml::as.yaml(list(core = list(symbol = plan$symbol, studies = plan$studies, variables = variables), step = step)))
}
