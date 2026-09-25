# Credits one PR contributor in DESCRIPTION (`d`, a desc object, changed
# in place): `aut` if they changed files under R/, `ctb` otherwise. Adds
# new people and upgrades an existing entry to `aut` (dropping `ctb`);
# never downgrades or removes anyone and leaves other roles (cre, cph, ...)
# alone. Returns a report line for the suggestion PR, or NULL if nothing
# changed.
credit_contributor <- function(d, name, r_files) {
  role <- if (length(r_files) > 0) "aut" else "ctb"
  reason <- if (role == "aut") {
    shown <- paste0("`", utils::head(r_files, 3), "`", collapse = ", ")
    more <- if (length(r_files) > 3) sprintf(" and %d more", length(r_files) - 3) else ""
    sprintf("changed %s%s", shown, more)
  } else {
    "no changes under `R/`"
  }

  authors <- d$get_authors()
  idx <- find_author(authors, name)
  if (is.na(idx)) {
    d$add_author(given = name, role = role)
    return(sprintf("- **%s**: added as `%s` (%s)", name, role, reason))
  }

  person <- authors[idx]
  roles <- unlist(person$role)
  if (role == "aut" && !"aut" %in% roles) {
    d$add_role("aut", given = person$given, family = person$family)
    if ("ctb" %in% roles) d$del_role("ctb", given = person$given, family = person$family)
    new_roles <- setdiff(c(roles, "aut"), "ctb")
    return(sprintf("- **%s**: `%s` → `%s` (%s)", name, paste(roles, collapse = ", "), paste(new_roles, collapse = ", "), reason))
  }
  NULL
}
