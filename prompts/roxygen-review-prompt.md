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

For each field: if existing content is already accurate and meets the
guidance, return that same content essentially unchanged (do not reword
something already correct). Treat placeholder or lazy content (e.g.
"XXXXX", "TODO", "tbd") and stale content (e.g. an outdated example
server) as inadequate and rewrite it. List every field you actually
changed in changed_tags.

Do not include export or import directives anywhere in your answer —
those are handled entirely outside this review and are not part of any
field.

Call the submit_review tool with your result. Do not write any prose
response — only call the tool.
