# scan-mode: all — rewrites the file directly with the new roxygen block.
write_in_place <- function(path, parsed, new_block) {
  lines <- parsed$lines
  new_lines <- strsplit(new_block, "\n")[[1]]
  before <- if (parsed$pre_end >= 1) lines[seq_len(parsed$pre_end)] else character(0)
  after  <- lines[seq(parsed$fn_start, length(lines))]
  writeLines(c(before, new_lines, parsed$gap_lines, after), path)
}
