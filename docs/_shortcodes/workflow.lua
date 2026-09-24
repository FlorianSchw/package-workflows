-- Shortcodes that build reference content straight from the repo, so the
-- site can't drift from the workflows:
--   {{< wf-inputs FILE >}}       inputs table of .github/workflows/FILE
--   {{< wf-secrets FILE >}}      secrets table of .github/workflows/FILE
--   {{< wf-permissions FILE >}}  permissions the caller job must grant
--   {{< example FILE >}}         examples/FILE as a copyable code block
-- The workflow YAML is parsed by pandoc itself (as a YAML metadata block),
-- which keeps descriptions as Markdown, e.g. `code` renders as code.

local function repo_path(...)
  return pandoc.path.join({ quarto.project.directory, "..", ... })
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then error("cannot read " .. path) end
  local text = f:read("a")
  f:close()
  return text
end

local function load_workflow(file)
  local text = read_file(repo_path(".github", "workflows", file))
  return text, pandoc.read("---\n" .. text .. "\n---\n", "markdown").meta
end

-- Keys of a YAML map in file order (Lua tables don't keep it), found as
-- `<indent>key:` lines after the section header.
local function ordered_keys(text, section, map)
  local start = text:find("\n%s*" .. section .. ":%s*\n") or 1
  local keys = {}
  for key in pairs(map) do
    local pos = text:find("\n%s+" .. key:gsub("%-", "%%-") .. ":", start)
    table.insert(keys, { key = key, pos = pos or math.huge })
  end
  table.sort(keys, function(a, b) return a.pos < b.pos end)
  local out = {}
  for _, k in ipairs(keys) do table.insert(out, k.key) end
  return out
end

local function value_inlines(v)
  if v == nil then return pandoc.Inlines({}) end
  local t = pandoc.utils.type(v)
  if t == "boolean" then return pandoc.Inlines({ pandoc.Code(tostring(v)) }) end
  -- Values are shown as code: undo the typographic quotes pandoc adds.
  local s = pandoc.utils.stringify(v):gsub("“", "\""):gsub("”", "\""):gsub("‘", "'"):gsub("’", "'")
  if s == "" then return pandoc.Inlines({ pandoc.Code("''") }) end
  return pandoc.Inlines({ pandoc.Code(s) })
end

local function cell(inlines) return { pandoc.Plain(inlines) } end

local function spec_table(file, section, with_default)
  local text, meta = load_workflow(file)
  local map = meta["on"] and meta["on"].workflow_call and meta["on"].workflow_call[section]
  if not map then
    return pandoc.Para({ pandoc.Emph("None.") })
  end

  local header = { cell("Name"), cell("Required") }
  if with_default then table.insert(header, cell("Default")) end
  table.insert(header, cell("Description"))

  local rows = {}
  for _, name in ipairs(ordered_keys(text, section, map)) do
    local spec = map[name]
    local required = spec.required == true
    local row = { cell({ pandoc.Code(name) }), cell(required and "yes" or "no") }
    if with_default then
      table.insert(row, cell(required and pandoc.Inlines({}) or value_inlines(spec.default)))
    end
    table.insert(row, cell(spec.description or pandoc.Inlines({})))
    table.insert(rows, row)
  end

  local aligns, widths = {}, {}
  for _ in ipairs(header) do
    table.insert(aligns, pandoc.AlignDefault)
    table.insert(widths, 0)
  end
  return pandoc.utils.from_simple_table(pandoc.SimpleTable({}, aligns, widths, header, rows))
end

local rank = { none = 0, read = 1, write = 2 }

-- Union of workflow-level and job-level permissions, highest level wins.
local function permissions_block(file)
  local _, meta = load_workflow(file)
  local merged, order = {}, {}
  local function add(perms)
    if not perms or pandoc.utils.type(perms) ~= "table" then return end
    for scope, level in pairs(perms) do
      local l = pandoc.utils.stringify(level)
      if merged[scope] == nil then table.insert(order, scope) end
      if merged[scope] == nil or rank[l] > rank[merged[scope]] then merged[scope] = l end
    end
  end
  add(meta.permissions)
  for _, job in pairs(meta.jobs or {}) do add(job.permissions) end

  if #order == 0 then
    return pandoc.Para({ pandoc.Str("No"), pandoc.Space(), pandoc.Str("special"), pandoc.Space(),
      pandoc.Str("permissions"), pandoc.Space(), pandoc.Str("needed.") })
  end
  table.sort(order)
  local lines = { "permissions:" }
  for _, scope in ipairs(order) do
    table.insert(lines, "  " .. scope .. ": " .. merged[scope])
  end
  return pandoc.CodeBlock(table.concat(lines, "\n"), pandoc.Attr("", { "yaml" }))
end

return {
  ["wf-inputs"] = function(args)
    return pandoc.Blocks({ spec_table(pandoc.utils.stringify(args[1]), "inputs", true) })
  end,
  ["wf-secrets"] = function(args)
    return pandoc.Blocks({ spec_table(pandoc.utils.stringify(args[1]), "secrets", false) })
  end,
  ["wf-permissions"] = function(args)
    return pandoc.Blocks({ permissions_block(pandoc.utils.stringify(args[1])) })
  end,
  ["example"] = function(args)
    local file = pandoc.utils.stringify(args[1])
    local text = read_file(repo_path("examples", file)):gsub("%s+$", "")
    -- Quarto adds its filename header before shortcodes are resolved, so
    -- build the same markup it would produce.
    local header = pandoc.RawBlock("html", '<div class="code-with-filename-file"><pre><strong>.github/workflows/'
      .. file .. '</strong></pre></div>')
    return pandoc.Blocks({
      pandoc.Div({ header, pandoc.CodeBlock(text, pandoc.Attr("", { "yaml" })) }, pandoc.Attr("", { "code-with-filename" })),
    })
  end,
}
