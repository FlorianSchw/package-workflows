# Tool schema for the analysis scripts. Claude returns each requested step
# as sections of plain code plus notes; R assembles the script files,
# checks the calls and runs them. Enums keep the answer inside what exists:
# step ids from the plan (`step_ids`, only the steps asked for) and, for
# "possible with another package" notes, package names from the catalogue
# (`catalogue_names`, retired packages already removed).
build_analysis_tool <- function(step_ids, catalogue_names) {
  note_package <- list(type = "string", description = "For kind other_package: the catalogue package that would make this possible (server package name). Empty string otherwise.")
  if (length(catalogue_names) > 0) note_package$enum <- as.list(c("", catalogue_names))

  list(
    description = "Submit the analysis script steps as plain code sections and notes. Never assemble files, headers or markers yourself; R does that.",
    input_schema = list(
      type = "object",
      properties = list(
        steps = list(
          type = "array",
          description = "One entry per requested step, in plan order.",
          items = list(
            type = "object",
            properties = list(
              step_id = list(type = "string", enum = as.list(step_ids), description = "The step's id from the plan."),
              sections = list(
                type = "array",
                description = "The step's code, split into self-contained sections of a few related calls each. Empty if nothing in the step is possible with the installed packages.",
                items = list(
                  type = "object",
                  properties = list(
                    purpose = list(type = "string", description = "One line: what this section does, for a comment above it."),
                    code = list(type = "string", description = "Plain, runnable R code. No comment header, no login or logout.")
                  ),
                  required = list("purpose", "code")
                )
              ),
              notes = list(
                type = "array",
                description = "What could not be written with the installed packages, and limitations the analyst should know.",
                items = list(
                  type = "object",
                  properties = list(
                    kind = list(type = "string", enum = list("other_package", "missing_function", "limitation"), description = "other_package: a catalogue package would make it possible. missing_function: no known DataSHIELD package offers it. limitation: possible, but restricted (e.g. no individual-level diagnostics because of disclosure control)."),
                    package = note_package,
                    text = list(type = "string", description = "One or two sentences for the analyst: what is affected and why.")
                  ),
                  required = list("kind", "package", "text")
                )
              )
            ),
            required = list("step_id", "sections", "notes")
          )
        )
      ),
      required = list("steps")
    )
  )
}
