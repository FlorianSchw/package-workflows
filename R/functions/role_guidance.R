# Builds the DataSHIELD role-specific guidance text (client/server) folded
# into the review prompt. demo_snippet is the canonical multi-study login
# example from build_demo_login_snippet(), or NULL when the package has no
# matching study group — in which case no example guidance is added.
role_guidance <- function(datashield, ds_type, role_guidance_config, demo_snippet) {
  if (!isTRUE(datashield)) return("")

  if (identical(ds_type, "client")) {
    text <- build_role_guidance_text(role_guidance_config$client)
    if (!is.null(demo_snippet)) {
      demo_intro <- paste(unlist(role_guidance_config$client$demo_environment), collapse = " ")
      text <- paste(text, "", demo_intro, "", demo_snippet, sep = "\n")
    }
    text
  } else if (identical(ds_type, "server")) {
    build_role_guidance_text(role_guidance_config$server)
  } else {
    ""
  }
}
