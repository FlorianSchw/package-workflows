# Collapsible groups of the suggestion reports, styled per
# config/report-style.yml (report_style()). `groups` is a list of
# list(title, lines). Always ends with a blank line: without it, Markdown
# after the last `</details>` would be swallowed into the HTML block.
report_groups <- function(groups, style = report_style()) {
  summary <- function(title) {
    h <- style$group_heading
    if (identical(h, "bold")) sprintf("<b>%s</b>", title)
    else if (identical(h, "plain")) title
    else sprintf("<h%d>%s</h%d>", as.integer(h), title, as.integer(h))
  }
  gap <- if (isTRUE(style$blank_line_between_groups)) "" else character(0)
  blocks <- lapply(groups, function(g) {
    c(sprintf("<details><summary>%s</summary>", summary(g$title)), "", g$lines, "", "</details>")
  })
  c(unlist(Map(function(b, last) c(b, if (!last) gap), blocks, seq_along(blocks) == length(blocks))), "")
}
