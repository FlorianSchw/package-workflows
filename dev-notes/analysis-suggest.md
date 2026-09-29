# Analysis starter scripts (idea, in design)

Status: **stage 1 built (2026-09-30), tested locally, not yet run in CI**
(design started 2026-09-29). See "Implementation" below.
Name (decided 2026-09-30): **`datashield-analysis-suggest.yml`**.
Lowercase like all workflow files (in prose it stays "DataSHIELD"). It
follows the `<thing>-suggest` family, and branches are
`bot-suggest/analysis/…`. "initiate" was dropped because the workflow
keeps proposing updates after the first run; a "gets you started" message
can go in the docs page title (e.g. "Start a DataSHIELD analysis"). Fix
the name before the first release: it is part of every caller's `uses:`
path and the federation rules' `job_workflow_ref` claim. This note keeps
its file name `analysis-suggest.md`.

## Idea

A reusable workflow for DataSHIELD **analysis projects**, not for packages.
An analyst describes a whole analysis in a config file. A change to that
file starts a Claude session, like the roxygen and test suggestions. It
builds a starting DataSHIELD analysis script with:

- correct calls;
- assignment of aggregate results to R objects;
- data management;
- modelling and checks of model assumptions, where DataSHIELD allows
  them;
- figure and table files.

The config template and the caller workflow come with a new project from
`dsAnalysis::initProject()`.

The aim is to get people started with DataSHIELD, not to do their job.
The analysis stays the researcher's responsibility. This goes into the
README or the script header, not into the code logic.

## Decisions so far

### How changes are proposed

- **Always a suggestion PR** (`bot-suggest/…`), like the other bots. The
  first run matters most.
- **Incremental after the first run.** The config diff decides which
  sections are added or changed. Full regeneration into a separate folder
  was rejected.
  - **Marker comments:** each generated section carries one naming the
    config entries it came from, plus a checksum of the generated code.
  - **Analyst edits are safe:** a section whose code no longer matches its
    checksum was edited by the analyst. It is never changed; the PR only
    notes what the config change would affect.
  - **Removals:** a removed config entry gives a note in the PR, never a
    deletion.
  - **First run:** the same mechanism, starting from an empty script.

### Data and privacy

- **Claude never sees data**, only the plan in the config. This is a
  deliberate strength: analysts define hypotheses and methods up front,
  close to pre-registration, instead of exploring. The variable names and
  the plan themselves do go to the API; that's the obvious data
  protection point.
- **Data protection: a note, no opt-in** (decided 2026-09-30). The config
  content (variable names, levels, studies, tables, the plan) goes to the
  API; data, credentials and `01_DS_Login.R` never do. The note that the
  config content is sent to the Claude API, and must not contain anything
  confidential, belongs in the **config template header and the dsAnalysis
  README**, not in this repo. The docs page here only points to it.
  - **Why no `send-to-api` setting:** users are worldwide with different
    regulations, so it's the project's own decision, like hosting on
    GitHub. Metadata is increasingly meant to be public anyway (in Europe
    the EHDS asks studies to publish dataset metadata; the user thinks by
    2029). And an opt-in would mean analysts editing settings they don't
    understand.
- **Design goal: analysts never touch the workflow file.** Everything
  analysis-related lives in the config; the caller comes from dsAnalysis
  and just works. Most analysts will have no workflow knowledge, and the
  secrets setup (GitHub App / PAT) is already a hurdle — see the auth
  question below.
- **`.Renviron`** is in `.gitignore` when dsAnalysis creates the project.
  If a user undoes that, it's their responsibility. CI never connects to
  real servers and never uses real credentials.

- **`01_DS_Login.R` belongs to the analyst** (confirmed by the user). It is never generated or
  changed, and never sent to Claude, since credentials may be in it. What
  Claude needs (studies, tables, symbol `D`) comes from the config. R
  checks the file mechanically for hard-coded credentials (a literal
  `password = "…"` rather than `Sys.getenv()`). If it finds any, the PR
  comment warns that they are visible to everyone with repo access, and
  suggests moving them to `.Renviron`. The values are never shown.
- **Middleware doesn't matter.** Opal and Armadillo (MOLGENIS) differ only
  in `01_DS_Login.R` (the `DSOpal` vs `DSMolgenisArmadillo` driver).
  DSLite imitates the DataSHIELD server interface, so the workflow is the
  same for both. On Armadillo the installed server packages come from the
  study's *profile*; the config template should say where to look them up.

### Validation

- **CI runs in dsAnalysis's testing mode** (decided; the user left the
  choice to me). Where dsAnalysis comes from is a workflow input with a
  default (e.g. `dsanalysis-ref: FlorianSchw/dsAnalysis@main`), because
  the org/repo of dsAnalysis will likely change. dsAnalysis will be on
  CRAN in the future, which removes the `Remotes` clash below. CI:
  1. writes the mock data generated from the config to
     `utils/mock_data/bot-suggest/`, next to the CNSIM demo, which stays;
  2. updates `utils/setup/01_DSLite_Setup.R` with dsAnalysis's own
     functions (`add_dsPackage()` / `update_MockData()`, which use marker
     comments), so dsAnalysis stays the only owner of that format;
  3. runs `main.R` with `R_CONFIG_ACTIVE=testing`.

  The PR includes script, mock data and the updated DSLite setup. Its
  comment tells the analyst to set `R_CONFIG_ACTIVE = 'testing'`, restart
  R and run `main.R`: the identical setup CI ran. The alternative, an own
  DSLite harness in the workflow, would also work without dsAnalysis, but
  CI and local testing would differ. Consequence: the workflow depends on
  dsAnalysis.
  - **Versions:** what runs is decided by what CI installs. dsAnalysis's
    DSLite setup only loads what's installed (`library(DSLite)`,
    `defaultDSConfiguration(include = …)`), so the testing mode adds no
    version problem of its own.
  - **Install clash:** dsAnalysis's `DESCRIPTION` has
    `Remotes: datashield/dsBaseClient` (and dsSupportClient), i.e. GitHub
    HEAD, which would clash with or overwrite the pinned client versions.
    Fix: install the pinned DataSHIELD packages first, then dsAnalysis
    without dependencies, plus its non-DataSHIELD imports (fs, usethis,
    here, …); only its file functions are needed. Separately, a point for
    dsAnalysis itself: analysts get GitHub HEAD dsBaseClient, possibly
    newer than their servers' dsBase. It may be better to depend on CRAN
    releases.
  - **Staleness:** if the DSLite template lags behind, CI inherits it, and
    so does every analyst locally. CI will notice when the testing mode
    breaks.
  - **Interface:** the marker comments in `01_DSLite_Setup.R` and
    `dependencies.R` become an interface between dsAnalysis and the
    workflow; change them as deliberately as a workflow input.
  - **Wording:** the PR comment promises identical files and procedure,
    and the same versions only if the analyst installs what
    `dependencies.R` lists. The PR states the tested versions.

- **A script is only proposed after it has run.** It runs in CI against
  DSLite, with mock data **generated from the config**. The config's
  variable section is required and carries, per variable:
  - name and table;
  - type (numeric / binary / categorical);
  - levels or value range;
  - role (outcome, exposure, confounder, …).

  R builds a synthetic table with exactly those names, one per study, so
  the script uses the real names and runs unchanged. The CNSIM mock data
  shipped with dsAnalysis stays for learning, but isn't used for this
  check. A script that runs on mock data can still be statistically wrong;
  the run only catches syntax, function and object errors.
- **No invented functions or arguments.** Generated calls are checked
  against the installed client packages' `formals()` and help. The earlier
  `dsAnalysis_functions_metadata.json` / `FlorianSchw/datashield-workflows`
  metadata tryout will likely be removed, so it isn't a source.
- **Claude returns sections as fields** (purpose, code, objects created,
  output files); R assembles them into dsAnalysis's script structure
  (`01_DS_Login.R`, `02_QualityCheck.R`, …, `main.R`).

### Script files

- **At most 150 lines per script file** (user's proposal), counting all
  lines including comments and markers. R enforces it while assembling;
  a prompt instruction wouldn't be reliable.
- **Naming:** one topic per number, starting at `02_` (`01_` is the
  login), e.g. `02_DataManagement.R`, `03_Descriptives.R`,
  `04_Models.R`. Names come from the config sections. Overflow gets
  letters: `02a_…`, `02b_…`.
- **Splits happen only between sections.** A single section over 150
  lines gets its own file and a note in the PR.
- **Stable names:** later additions get the next free letter. Existing
  files are never renumbered.
- **`main.R`:** the bot updates a marked block that sources the files in
  order.
- **The template's `02_QualityCheck.R`, `03_DescriptiveStatistics.R`,
  `99_DSLiteLearning.R`** were empty placeholders for good practice
  (numeric order makes debugging help easier). The user is removing them
  from dsAnalysis (2026-09-30), so the bot's numbering starts at `02_`
  without conflicts. If a project still has such a file, the bot never
  overwrites it and continues after the highest number in use.

### Package versions

- **The config lists server-side packages with versions, per study.**
  Usable is what all studies have installed. If one study lacks a package,
  Claude points that out.
- **No client packages in the config**, and `renv.lock` isn't relied on
  either: many R users don't use renv, and right after `initProject()`
  nothing extra is installed.
  - **Pairing:** each server package has a client package, by the
    `…Client` naming convention or an explicit pairing from the catalogue.
  - **Version:** the same version as the server package. Otherwise the
    newest with the same major.minor, otherwise the newest, reported in
    the PR.
  - **In CI:** those client versions and the server packages at their
    config versions are installed.
  - **Sources:** most DataSHIELD packages are on GitHub only, not CRAN.
    The location comes from the catalogue's `github_link`, so the config
    names package and version only. CI checks sources in this order:
    1. CRAN, if the package is there;
    2. a GitHub tag or release matching the version;
    3. the default branch, if its `DESCRIPTION` version matches;
    4. otherwise, the mismatch is reported in the PR.

    An optional git ref (tag / commit SHA) in the config pins exactly,
    for packages that never tag.
  - **For the analyst:** the script states the client versions it assumed,
    and the install lines go into `dependencies.R`.
- **`dependencies.R`** exists so renv also records packages without a
  `library()` call, e.g. `dsBase`, which is only needed for DSLite. The bot
  edits only its own marked blocks, in dsAnalysis's marker-comment
  convention:
  1. client packages for the configured server packages (tested);
  2. server packages for local DSLite testing;
  3. **commented out:** client and server packages the study servers
     don't have yet, with what they would enable. renv ignores
     commented-out lines, so nothing is installed by accident.
     Uncommenting lets an analyst try the functions locally in testing
     mode before the servers have them, which can help when asking data
     owners to install a package.

  The file's path is a config entry, defaulting to where `initProject()`
  puts it (project root); its final location isn't decided.

### Package catalogue and gaps

- **A config entry points to the DataSHIELD package catalogue.** Default:
  `https://packages.datashield.org/packages.json`, built nightly from
  `FederatedMethods/packages` (`package_list.csv` + DESCRIPTION / GitHub /
  CRAN). On 2026-09-29 it had 70 packages with name, description, status,
  links, version and dependencies. Its `functions` field exists but is
  empty everywhere, so for now judgements are at package level only.
- **The output falls into three categories:**
  1. **Possible now** (installed server packages): code, checked and run
     on mock data. Only this category produces code.
  2. **Possible with another package:** only a note in the PR. Claude may
     only name catalogue packages (an enum in the tool schema), and R
     checks that the package exists and isn't `retired`. Until the
     catalogue has function lists these are hints, not guarantees.
     Possible later: install the package in CI and try it in DSLite.
  3. **Not possible with any known package (a gap):** described in the PR
     comment, plus the issue link below.

### Gap reports: an "Open issue" link, no secrets

The workflow runs in the analyst's repo. Its `GITHUB_TOKEN` can't write to
another repo, and creating issues elsewhere automatically would need a
credential in every analyst repo:

- a PAT: anyone with write access to such a repo could use it;
- a GitHub App private key: handed to every analyst, open to spam, and a
  key rotation means every repo updates its secret;
- or a hosted relay service.

**Decision:** the PR comment contains a **prefilled "Open issue" link**
(`https://github.com/<owner>/<repo>/issues/new?template=…&title=…&body=…`).
The analyst clicks it and creates the issue under their own account.

- **No secrets, no permissions:** anyone can open issues in a public repo.
- **Privacy:** a gap description can reveal an unpublished research
  question, and the collection repo is public. The analyst sees and
  confirms what gets published.
- **Structure:** an issue template in the collection repo sets labels and
  layout. Labels in the URL are only applied for users with triage rights,
  so the template is the reliable way.
- **Nothing is lost:** if nobody clicks, the gap is still in the PR comment.
- **Target:** configurable (owner/repo). For now one of the user's repos.
  Proposed long-term home: a **dedicated repo in the FederatedMethods
  organisation**, e.g. `FederatedMethods/function-requests`, next to the
  package catalogue. That needs agreement from the organisation's
  maintainers; technically it needs only the repo and an issue template.

### Configurability

Like the other suggestion workflows, shared defaults can be overridden per
project by a file at the same path (`resolve_shared_path()`). Candidates:

- the prompt and guidance on DataSHIELD analysis conventions;
- mock data settings: rows per study, missing-value share, seed;
- the catalogue URL and the issue target repo;
- file paths: `dependencies.R`, script folder, mock data folder;
- section order and structure.

## Implementation (stage 1, 2026-09-30)

Files:
- **Workflow:** `.github/workflows/datashield-analysis-suggest.yml`, with
  inputs `plan-file` (default `config/analysis-plan.yml`),
  `dsanalysis-repository` and `dsanalysis-ref`, and the same secrets as
  the other bot suggestions. The example caller is
  `examples/datashield-analysis-suggest.yml`: push on the plan file on
  any branch, plus `workflow_dispatch`. The job skips `bot-suggest/*`
  refs.
- **Code:** entry script `R/suggest_datashield_analysis.R`; functions in
  `R/functions/analysis/`, which use only `shared/`.
- **Settings:** `config/analysis-suggest.yml` holds everything
  adjustable without code. Both config files are overridable per
  project, and a copy replaces the file completely. It covers:
  - mock data (rows, missing share, seed, folder);
  - line limit, numbering (first number, reserved numbers), repair
    rounds, test-run timeout;
  - project paths;
  - block markers (an interface with dsAnalysis);
  - variable types with aliases (`numeric`, `binary`, Opal's `decimal`,
    …) mapped to how mock data is generated;
  - catalogue URL, client suffix, excluded functions (login/logout),
    credential pattern, gap issue repo.
- **Texts:** `config/analysis-texts.yml` holds everything the analyst
  reads: script header, `dependencies.R` comments, step statuses, notes,
  PR report and the issue template. Placeholders are `{{KEY}}`, filled
  with the shared `fill_template()`, which stops if a placeholder has no
  value.
- **Claude:** the `datashield-analysis` profile in `config/claude.yml`
  (Opus 5, adaptive thinking); prompt `prompts/analysis-script-prompt.md`.
- **Still in code, on purpose:**
  - the step file marker line (parsed by regex);
  - the check messages meant for Claude's repair round;
  - maintainer errors (setup failures);
  - the install source order.

Flow:
1. `read_analysis_plan()` / `validate_analysis_plan()` fail fast with
   all core problems. Defaults: symbol `D`, step id from the title.
2. Each step is classified by its files' marker line
   (`find_bot_step_files()`):
   - **new** — no files yet;
   - **changed** — untouched files, but the plan hash differs;
   - **unchanged**;
   - **edited** — never overwritten; a note if its plan entry changed.

   A step whose files exist but that is no longer in the plan is
   **removed**: note only.

   If nothing is new or changed, there is no Claude call.
3. Install the usable server packages (`usable_server_packages()`, on
   all studies, lowest version) and their clients
   (`install_ds_package()`, via pak: CRAN → tag `v<ver>` → tag `<ver>` →
   default branch).
4. Mock data: `generate_mock_data()` → `utils/mock_data/bot-suggest/<server>.rda`.
   The DSLite setup is updated via dsAnalysis's `update_MockData()` /
   `add_dsPackage()`, sourced from a checkout (not installed, so its
   `Remotes` can't clash). `add_dsPackage()` is only called for packages
   that are really missing, which works around its bug.
   `check_login_file()`: connections name, credential warning,
   server/symbol mismatch.
5. Claude (`ask_claude_for_scripts()`) gets:
   - the installed client functions with signatures
     (`client_function_reference()`, ~150 functions for dsBaseClient);
   - the catalogue: non-retired, not installed, server packages only;
   - the existing bot scripts;
   - the plan;
   - the requested steps with their file numbers.

   The tool returns sections and notes per step; enums restrict step ids
   and note packages.
6. Checks (`test_step_scripts()`):
   - `check_ds_calls()` flags parse errors, unknown `ds.*` /
     `datashield.*` functions and unknown arguments;
   - `check_column_references()` requires every `"object$column"` string
     to name a plan variable or a `newobj` created by any step. Needed
     because DSLite (permissive privacy level) returns `NA` with "VALID
     ANALYSIS" for an unknown column instead of an error, so the test run
     can't catch invented variables;
   - `run_analysis_scripts()` runs the DSLite setup plus all bot scripts
     in file order via `callr`: `R_CONFIG_ACTIVE=testing`, no project
     `.Rprofile` (renv), no tokens in the environment.

   There is one repair round for failing steps, with their code and
   errors. A still-failing step is not proposed; a changed step keeps its
   old files.
7. Output:
   - **Step files:** `assemble_step_files()` writes `R/NN[a-z]_Title.R`
     files of at most 150 lines, split between sections.
   - **Notes-only files:** a step with no code gets a file with its notes
     as comments, so the gap is visible and the step isn't requested
     again every run.
   - **`R/main.R` block:** source lines for all bot scripts.
   - **`dependencies.R` block** (one block, three parts): packages
     already listed "not yet on servers" stay until the servers have
     them.
   - **Report:** `format_analysis_report()` → `suggestion_report.md`
     (the PR body) and the job summary.
   - **PR:** `commit-updated-files` in `changed` mode opens
     `bot-suggest/analysis/<branch>` → the pushed branch.

Marker formats (an interface; the dsAnalysis template can include the two
blocks empty):
- script, first line: `#### bot-suggest: step=<id> plan=<hash> content=<hash>`.
  `content` covers the rest of the file, so any edit counts. `plan`
  hashes the step entry plus the core (symbol, studies, variables).
- `R/main.R`: `#### bot-suggest: scripts (updated by datashield-analysis-suggest)`
  … `#### bot-suggest: scripts end`.
- `dependencies.R`: `#### bot-suggest: packages (updated by datashield-analysis-suggest)`
  … `#### bot-suggest: packages end`.

If a block is missing, it is appended at the end of the file.

Tested locally (2026-09-30) on a project built from the dsAnalysis
templates, with Claude and the installs replaced by stand-ins and DSLite
with dsBase 6.3.5 real:
- first run: 4 steps, a repair round for an invented argument, a
  notes-only step, and the report with the issue link;
- no change: no Claude call;
- edited script + plan change: left alone, with a note;
- changed step: rewritten under the same number;
- a failed changed step keeps its old script;
- "not yet on servers" packages kept across runs;
- the renv `.Rprofile` is skipped;
- a broken plan lists all problems.

**Refactoring pass (2026-09-30).** The entry script's steps became
functions (`classify_plan_steps()`, `install_study_packages()`,
`assign_step_numbers()`, `test_step_scripts()`,
`format_repair_request()`, `update_dependencies_file()`), and both rounds
now run in one loop instead of closures with `<<-`. Two bugs the stand-in
answers had hidden were fixed:
- **Runtime errors were never detected.** The script list carried step
  ids as names, which `run_analysis_scripts()` kept, so the lookup by path
  found nothing. It now always names results by path.
- **Scripts of requested steps without a new version were left out of
  the test run**, so later steps missed their objects. The run now
  includes every bot script that has no new version.

Re-tested:
- a runtime error, and an unknown column, each leading to repair;
- a step Claude skips: its old script is kept and still runs before the
  next step;
- an edited script with a plan change.

**Configurability pass (2026-09-30).** The settings and texts described
above moved out of R. The two checks share `walk_code()` for walking the
code tree (with the "empty argument" handling in one place), and
`step_code()` for a step's code. `install_ds_package()` keeps a package
that is already installed at the right version, e.g. from a cached or
preinstalled library; dsBase pulls in heavy dependencies.

Re-tested:
- all scenarios, with a plan using the alias `numeric`;
- an unknown type: its message lists the allowed types;
- a project override of `analysis-texts.yml` changes the report.

**Open (stage 2): `ds.glmSLMA()` fails in the DSLite test run**, locally
with dsBase 6.3.5, even on the original data (`D`), while `ds.glm()`
works. Study-level meta-analysis code that works on real servers would
be rejected. Check in CI whether this is a DSLite limitation and, if so,
how to handle it (e.g. a list of functions whose test failures only
become notes). Random mock data also makes `glm.fit` warn about
convergence; harmless, warnings aren't treated as failures.

**Not yet tested:** a real Claude answer, the pak installs (CRAN/GitHub
tags), and the PR in CI. That needs the user's test repo created with
dsAnalysis, with the three Anthropic secrets.

## What dsAnalysis needs (checklist for the user, 2026-09-30)

Template (`initProject()`):
1. Remove the empty placeholders `02_QualityCheck.R`,
   `03_DescriptiveStatistics.R`, `99_DSLiteLearning.R` (planned by the
   user).
2. Add a config template `config/analysis-plan.yml` (decided: in a
   `config/` folder, the workflow's `plan-file` default), from
   [analysis-suggest-example-config.yml](analysis-suggest-example-config.yml),
   with the header saying the content goes to the Claude API.
3. Add the caller `.github/workflows/datashield-analysis-suggest.yml`, from
   this repo's `examples/` once built.
4. `R/main.R`: optionally an empty marked block for the bot's `source()`
   lines (markers under "Implementation"); without it the bot appends
   one.
5. `dependencies.R`: optionally the bot's empty marked block (one block
   with three parts: tested clients, DSLite server packages, not yet on
   the servers commented out); without it the bot appends one.
   Suggestion: `.gitignore` must not exclude `utils/mock_data/`; the bot
   commits its mock data there.

Interface — keep stable:

6. The step markers in `01_DSLite_Setup.R` (`#### Step 1: …` to
   `#### Step 7: …`), used by `add_dsPackage()` / `update_MockData()`,
   and the markers in `main.R` and `dependencies.R`.

Functions:

7. **Bug in `add_dsPackage()`:** when every given package is already
   present, `new_dsPackage_length` is 0, and the `1:0` loops write
   `library(Client)` and break block 4. It should be a no-op.
8. `update_MockData()` fits CI. Pass `table_names` so it doesn't parse
   `01_DS_Login.R`. Each `.rda` must hold an object named after its server
   (`study1.rda` → `study1`).

README:

9. The data protection note.
10. A setup guide: the three secrets, plus "Allow GitHub Actions to create
    and approve pull requests".
11. How to try it: `R_CONFIG_ACTIVE = 'testing'`, restart R, run `main.R`.

Package:

12. `DESCRIPTION`: replace `Remotes: datashield/dsBaseClient` with CRAN
    releases (planned).
13. For its own test suggestions (`datashield-type: utility`): `DSLite`
    and `dsBase` in Suggests.

## Open questions

- ~~**MVP scope**~~ Decided, in stages:
  1. config (studies, server packages, variables), mock data, data
     management and descriptives — the whole pipeline end to end;
  2. models and the assumption checks DataSHIELD allows;
  3. figures and tables as files;
  4. incremental updates. Markers and checksums are built in from stage 1.
- **Example analysis plan:** the user will provide one later; design the
  config fields against it.
- ~~**Scope of client packages**~~ Resolved by the two config fields:
  the installed server packages per study (only these produce code) and
  the catalogue URL (only for notes and package locations). Whatever the
  analyst lists is supported. Stage 1 is developed and tested against
  `dsBase` / `dsBaseClient`; other packages get checked deliberately once
  a real use case comes up.
- ~~**Data protection**~~ Decided: a note in the config template and the
  dsAnalysis README, no opt-in (see above).
- ~~**Auth per analysis repo**~~ Decided (2026-09-30): the same as roxygen
  and tests, to stay flexible while cost models for such services are
  still being discussed. The caller passes the Anthropic organisation,
  service account and federation rule IDs as secrets; the GitHub App
  (`app-client-id` / `app-private-key`) stays optional. So the caller
  decides who pays. Remaining hurdle: analysts set up three secrets per
  repo, so the dsAnalysis README needs a step-by-step guide.
  - **Simplifications for later** (checked against the WIF docs on
    2026-09-30). None needs a workflow change; only the setup
    description would change once the cost model is settled.
    1. **One rule for many repos:** a rule matches a `subject_prefix`
       with a trailing `*` (e.g. `repo:<org>/*`), exact claims (e.g.
       `job_workflow_ref` = this workflow at `main`), and/or a CEL
       `condition` (e.g. `repository_owner` in an allowlist, for personal
       accounts). With the `job_workflow_ref` match only our reusable
       workflow's job gets tokens; callers can't add steps to it.
    2. **The IDs aren't secrets:** org, service account and rule IDs are
       identifiers; the security is the signed GitHub JWT matching the
       rule. They could be plain values in the caller dsAnalysis ships.
    3. **No App needed:** analysis repos normally have no required
       checks, so `GITHUB_TOKEN`-created PRs are fine. They only need
       "Allow GitHub Actions to create and approve pull requests" (believed
       off by default; to verify), which can be set org-wide.

    Always set a workspace spending limit when many repos share one org.
  - **One model for all users** (user's wish: several models for
    different user groups would be complicated). Users always enter
    three secrets. A later central setup (option 1) changes only who
    issues the values — the same shared values for everyone — not the
    procedure or the workflow.
- ~~**Where it lives**~~ Decided for now (2026-09-30): a new docs section
  "Analysis projects" next to "Bot suggestions", and a repo description
  like "Reusable GitHub Actions for R packages and DataSHIELD analysis
  projects". The repo structure may change after feedback, e.g.
  DataSHIELD-only parts split from the rest. So build the workflow to be
  easy to move:
  - entry script `R/suggest_datashield_analysis.R` plus
    `R/functions/analysis/`, using only `shared/`;
  - clearly named `config/analysis-*` and `prompts/analysis-*` files;
  - only generic additions to `shared/`; DataSHIELD-specific helpers stay
    in its own folder.
- **Config shape** — first draft in
  [analysis-suggest-example-config.yml](analysis-suggest-example-config.yml)
  (CNSIM-based, 2026-09-30). It is expected to change a lot: the user
  will get input from field experts, and usability will be tuned. Plans
  differ widely (fields, ids, models, some without tables), so the
  design keeps flexibility:
  - **A small fixed core that R validates:** `symbol`, `studies`
    (server names + server packages), `variables` (shaped like an
    Opal/Armadillo dictionary: name, label, type, categories/range,
    role), `package-catalogue`. It is needed for the mock data and the
    package checks; validated fail-fast before any Claude call.
  - **Free `steps`:** an ordered list; only `title` is required, any other
    fields go to Claude as written. One step is one script number
    (`02_`, `03_`, letters on overflow). Markers use the step's `id`, or
    else its title; a rename counts as removed + added and gives a PR
    note, never a deletion.
  - **No table names:** the login assigns tables to the symbol, and
    scripts only use the symbol and server names. Those two must match
    `01_DS_Login.R`; R checks that mechanically
    (`builder$append(server = …)`, `symbol = …`) without sending the
    file to Claude.
