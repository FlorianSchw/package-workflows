# Layout settings of the suggestion reports from config/report-style.yml
# (see resolve_shared_path() for where it's looked up). Missing settings
# fall back to the defaults below.
report_style <- function() {
  defaults <- list(section_heading = 2, group_heading = 4, blank_line_between_groups = FALSE)
  path <- resolve_shared_path("config/report-style.yml")
  if (!file.exists(path)) return(defaults)
  modifyList(defaults, yaml::read_yaml(path))
}
