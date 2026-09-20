# Builds the DataSHIELD role-specific guidance text (client/server) folded
# into the review prompt, including the canonical demo example when a
# matching study group was found.
role_guidance <- function(datashield, ds_type, matched_group, example_env, role_guidance_config) {
  if (!isTRUE(datashield)) return("")

  if (identical(ds_type, "client")) {
    text <- build_role_guidance_text(role_guidance_config$client)
    if (!is.null(matched_group)) {
      demo_snippet <- build_demo_login_snippet(package_name, matched_group, example_env$server)
      demo_text <- paste(
        "",
        "Canonical current demo environment for the examples field — use this",
        "verbatim as the example code (do not add any comment markers, tag",
        "labels, or wrapper syntax yourself — the script adds that structure).",
        "This reflects DataSHIELD's typical multi-centric usage (multiple",
        "studies connected at once). Treat any existing example content that",
        "connects to only one server, or references a different server or VM",
        "setup, as outdated and replace it with this:",
        "",
        demo_snippet,
        sep = "\n"
      )
      text <- paste(text, demo_text, sep = "\n")
    }
    text
  } else if (identical(ds_type, "server")) {
    build_role_guidance_text(role_guidance_config$server)
  } else {
    ""
  }
}
