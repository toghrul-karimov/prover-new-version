# Lean formalisation protocol v2: specification

Draft 0.1, 2026-10-27. This file specifies the files, formats, commands and checks that the Runner, the prompts and the adapters are built against. The design behind it is in `DESIGN.md`; decision numbers in brackets refer to `DECISIONS.md`. Items marked **OPEN** are choices made for this draft that still need the human's agreement.

## 1. Conventions

- **Language:** the Runner and `verify` are Python 3.11 or later (D60). The host is Linux with Docker or Podman (D17).
- **Formats:** files written by people or the Planner are TOML (comments allowed). Files written by the Runner are JSON, or JSON Lines for logs. All text is UTF-8.
- **Paths** are relative to the campaign repository's root unless stated otherwise.
- **Times** are wall-clock seconds; timestamps are UTC, in ISO 8601.
- **Names:** a *task id* is lowercase, dot-separated words (`heights.bounds`). It is stable for the task's whole life and never reused.

## 2. Repositories and directories

Two kinds of repository (D65):

- **The protocol repository** (this one, `prover-new-version`) holds the Runner, `verify`, the adapters, the default prompts and templates, the lessons file carried between campaigns, and the documentation. A tagged commit of it is the *Runner version* recorded in receipts (D45).
- **Each campaign has its own local Git repository** with the Lean project and everything the campaign produces. The Runner is its only writer; the Planner works on its own clone and submits through Runner commands (D26).
  - **A remote is optional,** agreed with the human, and may not be needed. If one is configured (`campaign.remote`), the Runner pushes `main` after each commit; a failed push is retried later and never stops the campaign.
  - **Nothing that can be re-obtained by compiling is committed or pushed:** no `.lake/` build outputs, compiled `.olean` files, dependency checkouts, the build cache or the container image. These are listed in `.gitignore`, which the Runner writes at setup.
  - **Committed:** Lean sources, graph entries, stubs, target sheets, receipts, the configuration (without credentials), prompts and lessons.
  - **Kept locally, never in Git:** the runtime folder below (attempt workspaces, transcripts, logs, inbox, state, index and cache). Transcripts and attempt workspaces cannot be re-obtained, so they are preserved until the human removes them.

Campaign repository layout:

```
campaign.toml               configuration (section 4)
lean-toolchain              pinned Lean version
lakefile.toml               Lean project definition
lake-manifest.json          pinned dependencies, Mathlib by commit
<Lib>/...                   Lean sources, organised by the Planner
graph/<id>.toml             one entry per Lean file (section 3)
stubs/<id>.lean             current statements of each task (section 3.3)
targets/<id>.md             target sheets for top-level statements (D20, D32)
receipts/<id>.json          latest receipt per entry; history is in Git (section 7)
prompts/                    the campaign's copy of the role prompts (section 9)
lessons.md                  the campaign's lessons file (D46)
```

Runtime directory, outside the campaign repository (default `<campaign>/../<name>-runtime/`, set in `campaign.toml`):

```
state.json                  status of every entry (section 8)
events.jsonl                append-only event log
inbox/<item-id>.json        items needing a decision (section 10)
requests/                   command requests to the running Runner (section 5)
attempts/<attempt-id>/      workspace, transcript, logs, time used
index.jsonl                 lemma index (section 6.4)
cache/                      shared build cache of proved entries
```

Receipts and lessons are committed; attempt workspaces, transcripts and logs stay in the runtime directory, preserved until the human removes them.

## 3. The dependency graph

### 3.1 Graph entries

Every Lean file in the project has exactly one graph entry, `graph/<id>.toml`:

```toml
id = "heights.bounds"
kind = "task"                      # "definition" | "task" | "rewrite"
module = "Baker.Heights.Bounds"    # the Lean module; the file path follows from it
namespace = "Baker.Heights.Bounds" # public declarations must start with this (D15)
depends = ["heights.basic", "defs.height"]   # entries it uses; drives scheduling (D5, D14)
statements = ["height_bound", "height_bound_of_ne_zero"]   # theorems the task must prove
lemmas = ["Baker.Heights.Basic.height_nonneg", "Finset.prod_le_prod₀"]   # packet list (D16)
notes = """Route: bound each place separately, then multiply."""   # the Planner's advice
top_level = false                  # true for approved top-level statements (D20)
target = ""                        # "targets/<id>.md" when top_level
created_by = "planner"             # "planner" | "fixer"
parent = ""                        # for entries created by a Fixer split: the original task
```

- **Definition entries** hold the Planner's definitions, instances and simple proofs about them (D41, D49). The Runner checks they compile with only the allowed axioms; they have no attempts.
- **Task entries** are proof work for Provers (D12).
- **Rewrite entries** are used only by the optional rewrite after a campaign (D57, D59).

Definition files get graph entries like tasks, so the same scheduling, re-checking and receipts cover them (D66).

### 3.2 Rules the Runner enforces on the graph

- Every `depends` id exists and is a definition or a task; the graph has no cycles (D26).
- Every module named in a file's `import` lines is either an entry listed in `depends`, a dependency package (Mathlib and its dependencies), or a proved entry (D14).
- `statements` lists at least one theorem for a task; every listed theorem exists in the stub, inside `namespace`.
- An entry that others depend on cannot be withdrawn until they change (D53).

### 3.3 Stubs: current statements

`stubs/<id>.lean` is the task's current statement: the task's file as the Planner submitted it, with every listed theorem stated in full and proved by `sorry`. The task's own file starts as a copy of its stub. The Prover then fills in the proofs; the stub stays as the record of what must be proved. Changing a statement means submitting a new stub (`revise`), which triggers the re-check of section 11.

## 4. Configuration: `campaign.toml`

Proposed by the Planner in one message and confirmed by the human (D25, D32, D63).

```toml
[campaign]
remote = ""                        # optional Git remote, agreed with the human (D65)
name = "baker-three-logs"
library = "Baker"                  # Lean library holding the project's sources
runtime_dir = "../baker-three-logs-runtime"

[roles.prover]
implementation = "agent"           # "agent" | "api" (D63)
agent = "claude-code"              # "claude-code" | "codex"     (implementation = "agent")
api = ""                           # "chat-completions" | "anthropic"   (implementation = "api")
endpoint = ""                      # API base URL                (implementation = "api")
model = "claude-sonnet-5-5"
reasoning = "medium"
time_limit = 900

[roles.fixer]
implementation = "agent"
agent = "codex"
model = "<Codex model name>"       # chosen in the configuration step
reasoning = "high"
time_limit = 1800

[roles.planner]                    # recorded for the record; the human starts the Planner
agent = "claude-code"
model = "claude-opus-5-5"

[resources]
attempts = 6                       # N (D18)
memory_cap = "12g"                 # per container, swap off
check_time_limit = 600

[budget]
spending_cap = ""                  # optional; covers Planner worker agents too (C15)
wall_time_cap = ""                 # optional

[network]
provider_hosts = ["<provider host>", "..."]   # what agent containers may reach (D64); exact hosts verified by setup-check

[notify]
command = ["notify-send", "Lean campaign"]   # receives the message on standard input
summary_every = 7200
inbox_unread_alert = 3600          # alert the human if the inbox goes unread this long (D28)

[credentials]
api_key_env = ""                   # name of the environment variable holding an API key
agent_login_dirs = { "claude-code" = "~/.claude", "codex" = "~/.codex" }   # shared into agent containers (D64)
```

Any setting may change during the campaign and applies to attempts started afterwards (D53). Keys and tokens are never written to the repository.

## 5. Commands

The Runner is one long-running program, started with `runner run`. Every other command writes a request into the runtime directory's `requests/` folder; the running Runner applies it and writes the result back, and the command prints it. So the Runner remains the only writer of the campaign repository and of its state.

Commands talk to the Runner through request files, not a network socket (D67). Throughout, the Runner's code should stay simple: no feature is worth complicated code when a plain file or a plain command will do.

| Command | Who | Effect |
|---|---|---|
| `runner setup-check` | human, Planner | Runs the host checks of section 12.4 |
| `runner run` | human | Starts the Runner. After an unclean stop it starts paused and posts an inbox item (D52) |
| `runner status [--json]` | anyone | Counts by status, tasks that can be attempted, the depth, running attempts, open inbox items, spending so far |
| `runner inbox [--for planner\|human]` | anyone | Lists open inbox items |
| `runner pause [--now]` | human | Stops starting attempts; with `--now`, also interrupts running ones (D52) |
| `runner resume` | human | Applies changes made meanwhile and continues interrupted attempts (D52) |
| `runner submit <entry.toml> <file.lean>` | Planner | Adds a graph entry with its stub or definition file (D26) |
| `runner revise <id> [<entry.toml>] [<file.lean>]` | Planner | Changes an entry; triggers the re-check of section 11 (D53) |
| `runner withdraw <id>` | Planner | Removes an entry nobody depends on |
| `runner resolve <item-id> [--note <text>]` | Planner, human | Closes an inbox item |
| `runner approve <target-id>...` | human | Approves top-level statements; creates the approval tag (D20) |
| `runner heartbeat-pass` | human | Runs the end-of-campaign heartbeat pass (D23) |
| `lean-verify <repo> <commit>` | anyone | Independent check (section 12.3); a separate program |

## 6. The Prover

### 6.1 The packet

Every attempt, whatever the implementation, receives:

- the task's stub (the statements to prove) and the Planner's `notes`;
- for each name in `lemmas`, its full statement (looked up in the index or Mathlib);
- a table of contents: one line per proved module, its name and module docstring;
- the time limit and how much remains;
- after a failed check or a re-check: the previous proof and the diagnostics.

### 6.2 Tools

| Tool | Does |
|---|---|
| `read_file(path, start?, end?)` | Reads a project or dependency Lean source, or the entry's notes |
| `write_task_file(content)` | Replaces the task file (only the task's own file is writable) |
| `edit_task_file(old, new)` | Replaces one unique piece of the task file |
| Lean server tools | Goal and term-goal at a position, hover, completions, diagnostics, file outline, declaration location, local search, run a snippet, try several tactics, references: as in Baker's runner |
| `search_index(query)` | Matching lines from the project's lemma index (section 6.4) |
| `loogle(query)`, `leansearch(query)` | Mathlib search, carried out by the Runner outside the container (D54) |
| `check()` | Asks for the acceptance check; ends the Prover's turn (D43) |

A model-API Prover gets these as tool definitions. An agent-tool Prover gets the Lean server tools from a Lean server in its container, and the Runner-provided tools (`search_index`, `loogle`, `leansearch`, `check`) through a small MCP server in the container that forwards to the Runner over a Unix socket mounted into the container. Its own file tools replace `read_file`, `write_task_file` and `edit_task_file`, limited by the container (D64).

### 6.3 Attempt lifecycle

1. The Runner creates the attempt's workspace: the campaign commit plus the task file; the dependency packages and the shared build cache are mounted read-only.
2. It starts the Prover: the model-API loop, or the agent tool through its adapter, inside the container.
3. On `check()`: the attempt container is stopped completely; the check runs (section 7). Pass: done. Fail: a fresh container on the same workspace; the Prover resumes with the diagnostics and the remaining time (the model-API loop appends a message; an agent tool resumes its session through the adapter).
4. At the time limit the Runner stops the attempt. The attempt then ends without a pass, and the Fixer is called (D34).
5. The Prover's final message, if it is blocked, states the obstacle precisely (section 9).

Time counts from the attempt's start, including tools and checks; it is written to `attempt.json` every few seconds (D52).

### 6.4 The lemma index

After each acceptance, the Runner adds a line to `index.jsonl` for each public declaration of the proved entry: full name, statement (pretty-printed, cut at a fixed length), module, first line of its docstring. `search_index` returns at most 20 matching lines, matching on words in the name, the statement and the docstring.

## 7. The acceptance check

Runs in its own container, offline, on a fresh copy: the campaign commit plus the submitted file. Steps:

1. **Static scan of the submitted file.** Rejects:
   - `set_option maxHeartbeats` except as `set_option maxHeartbeats N in` directly before one declaration, and any `N = 0` (D23);
   - global `instance`, `@[simp]`, `notation`, `infix`, `macro`, `syntax` and `attribute [...]` without `local` or `scoped` (D15);
   - **OPEN 7.1:** commands that run code during compilation: `#eval`, `run_cmd`, `run_tac`, `run_elab`, `initialize`, `elab`, and the `unsafe`, `implemented_by` and `extern` keywords. Not decided yet; none of Baker's 727 task files used any.
2. **Build** the task's module with `lake build`, within `check_time_limit`.
3. **Audit,** in Lean, for each name in `statements`:
   - it exists inside the task's namespace and is a theorem;
   - its type is definitionally equal to the stub's statement. The stub is compiled under a separate namespace for the comparison, as in Baker's audit;
   - its axioms (collected transitively) are only `propext`, `Classical.choice` and `Quot.sound`. Since a task imports proved entries only, this also proves that it contains no `sorry`.
4. **Module checks:**
   - every public declaration of the module starts with its namespace;
   - its imports satisfy section 3.2.

Deprecation warnings are ignored (D21).

**Receipt** (`receipts/<id>.json`), committed with the accepted file:

```json
{
  "id": "heights.bounds",
  "commit": "<campaign commit of the accepted file>",
  "runner_version": "<protocol repository tag>",
  "toolchain": "leanprover/lean4:v4.34.1",
  "image": "<container image digest>",
  "prompt_versions": {"prover": "<commit of prompts/prover.md>"},
  "implementation": {"role": "prover", "kind": "agent", "agent": "claude-code", "model": "claude-sonnet-5-5"},
  "author": "prover",
  "attempts": ["<attempt-id>"],
  "imports": ["Baker.Heights.Basic", "Mathlib.Algebra.Order.BigOperators.GroupWithZero.Finset"],
  "axioms": ["propext", "Classical.choice", "Quot.sound"],
  "heartbeat_raises": [],
  "time_used": 412,
  "accepted_at": "2026-11-02T14:03:11Z"
}
```

## 8. Statuses and state

| Status | Meaning |
|---|---|
| `waiting` | some dependency is not proved |
| `can-be-attempted` | all dependencies proved; waiting for a slot |
| `proving` / `fixing` | a Prover or Fixer attempt is running |
| `checking` | its acceptance check is running |
| `proved` | accepted, with a receipt |
| `interrupted` | stopped by a pause, crash or infrastructure problem; resumes with its remaining time (D52) |
| `needs-recheck` | its statement or a dependency changed (section 11) |
| `with-planner` | escalated, or failed after the Fixer (D7, D32) |

`state.json` holds every entry's status, its current attempt and its time used. It is rewritten atomically: write a new file, then rename it.

**Crash recovery** (D52): on start, the Runner reads `state.json`, removes leftover containers, marks entries that were `proving`, `fixing` or `checking` as `interrupted`, starts paused, and posts an inbox item for the human.

## 9. Prompts

The campaign's prompts live in `prompts/`, copied from the protocol repository's defaults at setup, and may change during a campaign (D50). Each attempt records the commit of the prompt it used.

- `prompts/prover.md`: the Prover's rules (checklist in `DESIGN.md` §16).
- `prompts/prover-rewrite.md`: for the optional rewrite (D59).
- `prompts/fixer.md`: the Fixer's rules.
- **The Planner's** instruction file (`CLAUDE.md` or `AGENTS.md`) and start prompt live in the Planner's own working folder, outside the campaign repository and its clones (C9).

## 10. The Fixer and the inbox

### 10.1 What the Fixer receives (D44)

A copy of the Prover's workspace, the packet, the last check's diagnostics, the Prover's final message, and the path of the Prover's transcript. Its tools are the Prover's, plus the two in 10.2.

### 10.2 What the Fixer returns

The Fixer writes `fixer-report.json` in its workspace and ends:

```json
{"outcome": "finish", "summary": "..."}
{"outcome": "split", "summary": "...",
 "new_entries": [{"entry": "<TOML text of graph/<id>.toml>", "stub": "<Lean text>"}],
 "candidate": "<path in the workspace of the original task's file using the new entries>"}
{"outcome": "escalate", "summary": "...", "reason": "false" | "needs-change" | "other",
 "affected": ["<task ids>"], "proposed_statement": "<optional Lean text>"}
```

- **Finish** goes to the check.
- **Split:** the Runner applies the four guards of D13. If they pass, it adds the new entries (`created_by = "fixer"`, `parent` set), keeps the candidate as the original task's saved proof (checked once the new entries are proved), and records an inbox notice for the Planner. A malformed report, or a failed guard, sends the task to the Planner, with the reason.
- **Escalate** sends it to the Planner; for a top-level statement, also to the human.

### 10.3 Inbox items

```json
{"id": "2026-11-02T14:10:00Z-0007", "for": "planner", "kind": "escalation",
 "entry": "heights.bounds", "summary": "...", "evidence": ["attempts/<id>/..."],
 "status": "open", "resolution": ""}
```

Kinds:
- for the Planner: `escalation`, `failed-after-fixer`, `split-notice`, `few-can-be-attempted`, `complete`;
- for the human: `infrastructure`, `unclean-stop`, `approval-needed`, `usage-limit`, `inbox-unread`.

## 11. Re-check after a change (D53)

When a stub or a definition file changes (`revise`):

1. **Affected entries:** the changed entry, plus every entry whose recorded imports (receipts) lead to it, directly or not.
2. **Cancel** attempts running on affected entries. They don't count as failures.
3. **Mark** affected entries `needs-recheck`.
4. **Re-check,** in dependency order: run the acceptance check on each entry's existing file against the current stubs.
   - Pass: a new receipt, `proved`.
   - Fail: the entry becomes `can-be-attempted` once its dependencies are proved, and the Prover starts from the previous proof and the new diagnostics.

A change to the Lean or Mathlib version re-checks every entry, after a full rebuild.

## 12. Containers, network, setup check and `verify`

### 12.1 Containers (D17, D18, D64)

- One image per campaign, built from the pins: Lean, the Mathlib build, the Lean server tools, and the Claude Code and Codex programs.
- Mounts:
  - `/work`: the attempt's workspace, writable;
  - `/deps`: dependency packages, read-only;
  - `/cache`: the shared build cache, read-only, with a private writable layer;
  - `/runner.sock`: the Runner tools socket (section 6.2);
  - agent containers only: the shared login folder for their tool.
- Memory cap from `campaign.toml`, swap off. A slot holds one container at a time.

### 12.2 Network

- Model-API attempts and checks: no network.
- Agent-tool attempts: only the hosts in `network.provider_hosts`, through the filtering proxy on the host. Their own web tools are turned off.

### 12.3 `lean-verify`

A separate program, independent of the Runner and short enough to read. Given a campaign repository and a commit:
1. it makes a clean checkout;
2. it builds everything in the pinned image, offline;
3. for every top-level entry in the approval tag, it checks that the statement equals the approved stub and that the axioms are only the allowed three;
4. it prints a report and exits non-zero on any failure.

### 12.4 `setup-check`

- Builds a tiny Lean file in the image.
- Runs the acceptance check on a good file and on bad files: a wrong statement, a forbidden axiom, a file-wide heartbeat setting, a global instance, a public declaration outside the namespace.
- Confirms the memory cap works.
- Makes one request per configured role.
- For agent tools: confirms that the agent cannot read or write outside its workspace, nor reach a host outside `provider_hosts`, and that two containers can share one login.
- Runs `lean-verify` on the result.

## 13. Lessons file

`lessons.md`, one section per lesson:

```markdown
## 2026-11-02 · Short title
**Lesson:** what was learned.
**Evidence:** tasks, receipts or logs.
**Suggested change:** to the Runner, prompts, settings or planning, if any.
```

## 14. Open items in this draft

- **7.1** Reject commands that run code during compilation.

Decided in review: 2.1 (D65), 3.1 (D66), 5.1 (D67).
