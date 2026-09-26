# Splits a job's `uses:` value that calls a reusable workflow into its
# parts: "owner/repo/.github/workflows/file.yml@ref" (another repository)
# or "./.github/workflows/file.yml" (the same repository). `label` is how
# the diagrams show it — always with the owner, since the same repository
# name can exist in several accounts: "owner/repo › file.yml@ref".
# Returns NULL for anything else (a job without `uses:`).
parse_workflow_ref <- function(uses) {
  if (is.null(uses) || !is.character(uses)) return(NULL)

  if (startsWith(uses, "./")) {
    path <- sub("^\\./", "", uses)
    return(list(local = TRUE, owner = NA, repo = NA, path = path, ref = NA,
                file = basename(path), key = path, label = basename(path)))
  }

  m <- regmatches(uses, regexec("^([^/]+)/([^/]+)/(.+\\.ya?ml)@(.+)$", uses))[[1]]
  if (length(m) == 0) return(NULL)
  list(local = FALSE, owner = m[2], repo = m[3], path = m[4], ref = m[5],
       file = basename(m[4]), key = uses,
       label = sprintf("%s/%s › %s@%s", m[2], m[3], basename(m[4]), m[5]))
}
