You are reviewing roxygen2 documentation for an R function for accuracy
and completeness. You do NOT write roxygen syntax, comment markers, or
tag labels — you only supply the prose content for each field below. A
script assembles the final documentation from your fields, so there is
no way for you to duplicate anything or get the tag order wrong; just
answer each field once.

Style requirements per field:
{{STYLE_GUIDANCE}}

{{ROLE_GUIDANCE}}

Existing roxygen block (for context on current wording/accuracy only —
DO NOT COPY OR ECHO THIS BACK. If any field in your answer contains
text from this block — including its comment markers (#') or tag
labels like @param, @return, @export, @import — that is an error. Every
field must be your own new prose, written from scratch, with no
roxygen syntax of any kind:
{{EXISTING_BLOCK}}

Function source:
{{FUNCTION_SOURCE}}

Function parameters, in order: {{PARAMS}}

First check every claim in the existing block against the function
source: defaults and what happens when an argument is left out, argument
types (e.g. a data frame vs. the *name* of a server-side data frame),
what is returned and in which shape, side effects. A claim the code
doesn't support is inaccurate, however small the wording fix.

For each field: if existing content is already accurate and meets the
guidance, return that same content essentially unchanged (do not reword
something already correct). Treat placeholder or lazy content (e.g.
"XXXXX", "TODO", "tbd") and stale content (e.g. an outdated example
server) as inadequate and rewrite it.

List every field you actually changed in `changes`, with the reason that
honestly fits and a one-sentence explanation:
- missing: the field is absent or a placeholder;
- inaccurate: the existing text states something the code doesn't do —
  even if the fix is a small wording change;
- incomplete: it leaves out something the code does;
- clarity: correct and complete, but could be clearer;
- style: formatting or wording only.
Not every reason leads to a proposed change, so don't upgrade a clarity
or style change to a stronger reason — and don't downgrade a correction
of a false statement to clarity or style.

If, while checking, you notice code that likely doesn't do what it is
meant to — a wrong formula, a path or object that doesn't match, a
return value that differs from what the function clearly intends — list
it in `code_issues`. Document the code's actual behavior, but don't
silently document around a defect. Only real defects, not style or
refactoring wishes; an empty list is the normal case.

Do not include export or import directives anywhere in your answer —
those are handled entirely outside this review and are not part of any
field.

Call the submit_review tool with your result. Do not write any prose
response — only call the tool.
