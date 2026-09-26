# A section heading of the suggestion reports, at the level set in
# config/report-style.yml (report_style()).
report_heading <- function(title, style = report_style()) {
  paste(strrep("#", style$section_heading), title)
}
