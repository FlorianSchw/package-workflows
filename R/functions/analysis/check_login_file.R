# Reads the analyst's real login file (01_DS_Login.R) mechanically — it is
# never sent to Claude — and returns list(connections, notes):
# - the name of the connections object (`conns` in the dsAnalysis
#   template), which the generated scripts pass as `datasources`;
# - a warning if a password or token is written into the file as text
#   instead of read with Sys.getenv() (the file is in the repository);
# - notes if its server names or symbol differ from the plan, since the
#   scripts are written for the plan's.
# Only line numbers are reported, never the values.
check_login_file <- function(path, plan) {
  notes <- character(0)
  if (!file.exists(path)) {
    return(list(connections = "conns", notes = sprintf("No login file at `%s`; the scripts assume the connections are called `conns`.", path)))
  }
  lines <- readLines(path, warn = FALSE)
  code <- sub("#.*$", "", lines)

  secret_lines <- grep("(password|pwd|passwd|token|secret)\\s*=\\s*[\"'][^\"']+[\"']", code, ignore.case = TRUE)
  if (length(secret_lines) > 0) {
    notes <- c(notes, sprintf(
      "**`%s` seems to contain credentials as plain text** (line %s). Everyone with access to this repository can read them. Move them to `.Renviron` and read them with `Sys.getenv()`, as the dsAnalysis template does.",
      path, paste(secret_lines, collapse = ", ")
    ))
  }

  text <- paste(code, collapse = "\n")
  pick <- function(pattern) {
    m <- regmatches(text, gregexpr(pattern, text, perl = TRUE))[[1]]
    sub(pattern, "\\1", m, perl = TRUE)
  }
  connections <- pick("([A-Za-z.][A-Za-z0-9._]*)\\s*(?:<<-|<-|=)\\s*(?:DSI::)?datashield\\.login\\s*\\(")
  connections <- if (length(connections) > 0) connections[1] else "conns"

  servers <- pick("server\\s*=\\s*[\"']([^\"']+)[\"']")
  planned <- vapply(plan$studies, function(s) s$server, character(1))
  if (length(servers) > 0 && !setequal(servers, planned)) {
    notes <- c(notes, sprintf(
      "The servers in `%s` (%s) differ from the plan (%s). The scripts use the plan's names, e.g. for results per study.",
      path, paste(sprintf("`%s`", servers), collapse = ", "), paste(sprintf("`%s`", planned), collapse = ", ")
    ))
  }
  symbol <- pick("symbol\\s*=\\s*[\"']([^\"']+)[\"']")
  if (length(symbol) > 0 && !identical(symbol[1], plan$symbol)) {
    notes <- c(notes, sprintf("`%s` assigns the data to `%s`, the plan says `%s`. The scripts use `%s`.", path, symbol[1], plan$symbol, plan$symbol))
  }

  list(connections = connections, notes = notes)
}
