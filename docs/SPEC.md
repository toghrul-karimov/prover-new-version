# Lean formalisation protocol v2: specification

Draft 0.2, 2026-10-27. This file specifies the files, formats, commands and checks that the Runner, the prompts and the adapters are built against. The design behind it is in `DESIGN.md`; decision numbers in brackets refer to `DECISIONS.md`. Every item raised in the review of draft 0.1 is settled (section 14).

## 1. Conventions

- **Language:** the Runner and `verify` are Python 3.11 or later (D60). The host is Linux, with bubblewrap 0.8 or later and systemd with cgroup v2 (D17, D95). Campaigns pin Lean v4.35.0 or later (D92).
- **Formats:** files written by people or the Planner are TOML (comments allowed). Files written by the Runner are JSON, or JSON Lines for logs. All text is UTF-8.
- **Paths** are relative to the campaign repository's root unless stated otherwise.
- **Times** are wall-clock seconds; timestamps are UTC, in ISO 8601.
- **Names:** a *task id* is lowercase, dot-separated words (`heights.bounds`). It is stable for the task's whole life and never reused.

## 2. Repositories and directories

Two kinds of repository (D65):

- **The protocol repository** (this one, `prover-new-version`) holds the Runner, `verify`, the adapters, the default prompts and templates, the lessons file carried between campaigns, and the documentation. A tagged commit of it is the *Runner version* recorded in receipts (D45).
- **Each campaign has its own local Git repository** with the Lean project and everything the campaign produces. The Runner is its only writer; the Planner works on its own clone and submits through Runner commands (D26).
  - **A remote is optional,** agreed with the human, and may not be needed. If one is configured (`campaign.remote`), the Runner pushes `main` after each commit; a failed push is retried later and never stops the campaign.
  - **Nothing that can be re-obtained by compiling is committed or pushed:** no `.lake/` build outputs, compiled `.olean` files, dependency checkouts, the build cache or the installed tools. These are listed in `.gitignore`, which the Runner writes at setup.
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
login/claude-code/, login/codex/   the campaign's own agent-tool logins, nothing else (D88)
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
assumption = false                 # definition entries only: true for an assumption (D68, D70)
target = ""                        # "targets/<id>.md" when top_level
created_by = "planner"             # "planner" | "fixer"
parent = ""                        # for entries created by a Fixer split: the original task
```

- **Definition entries** hold the Planner's definitions, instances and simple proofs about them (D41, D49). The Runner checks they compile with only the allowed axioms; they have no attempts.
- **Assumptions** (D68, D70): for a result the human wants under an assumption, the assumption is a definition entry with `assumption = true`, holding a named `def … : Prop` whose docstring cites its source. Statements that rely on it take it as an explicit hypothesis, for example `theorem main (hA : A) : P`. It is never a Lean `axiom`, so the allowed axioms stay the three. Target sheets list the assumptions a top-level statement uses.
- **Task entries** are proof work for Provers (D12).
- **Rewrite entries** are used only by the optional rewrite after a campaign (D57, D59).

Definition files get graph entries like tasks, so the same scheduling, re-checking and receipts cover them (D66).

### 3.2 Rules the Runner enforces on the graph

- Every `depends` id exists and is a definition or a task; the graph has no cycles (D26).
- Every module named in a file's `import` lines is either an entry listed in `depends`, a dependency package (Mathlib and its dependencies), or a proved entry (D14).
- **Stubs and definition files import only definition entries and dependency packages** (D98), never a task's file. The Runner refuses a `submit` or `revise` that breaks this. A task file may add imports of proved entries (D14); stating a theorem needs only definitions.
- `statements` lists at least one theorem for a task; every listed theorem exists in the stub, inside `namespace`.
- An entry that others depend on cannot be withdrawn until they change (D53).
- **Approval covers meaning** (D20, D69, D93). It covers each approved stub, every campaign file that stub imports, directly or indirectly, and the Lake configuration, `lean-toolchain` and `lake-manifest.json`. A `revise` that changes a covered file is held, not applied, and an `approval-needed` item goes to the human; `runner approve` applies it and moves the approval tag.

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
model = "<model name>"           # chosen in the configuration step
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
model = "<model name>"

[resources]
attempts = 6                       # N (D18)
memory_cap = "12g"                 # per sandbox, swap off
check_time_limit = 600

[budget]
spending_cap = ""                  # optional; covers Planner worker agents too (C15)
wall_time_cap = ""                 # optional

[network]
provider_hosts = ["<provider host>", "..."]   # what agent sandboxes may reach (D64, D96); exact hosts verified by setup-check

[notify]
command = ["notify-send", "Lean campaign"]   # receives the message on standard input
summary_every = 7200
inbox_unread_alert = 3600          # alert the human if the inbox goes unread this long (D28)

[check]
allow_code = []                    # files exempt from the code-running ban; only the human adds (D72)

[credentials]
api_key_env = ""                   # name of the environment variable holding an API key
# Agent-tool logins live in the runtime directory's login/ folder, created by `runner login` (D88).
```

Any setting may change during the campaign and applies to attempts started afterwards (D53). Keys and tokens are never written to the repository.

## 5. Commands

The Runner is one long-running program, started with `runner run`. Every other command writes a request into the runtime directory's `requests/` folder; the running Runner applies it and writes the result back, and the command prints it. So the Runner remains the only writer of the campaign repository and of its state.

Commands talk to the Runner through request files, not a network socket (D67). Throughout, the Runner's code should stay simple: no feature is worth complicated code when a plain file or a plain command will do.

| Command | Who | Effect |
|---|---|---|
| `runner setup-check` | human, Planner | Runs the host checks of section 12.5 |
| `runner run` | human | Starts the Runner. After an unclean stop it starts paused and posts an inbox item (D52) |
| `runner status [--json]` | anyone | Counts by status, tasks that can be attempted, the depth, running attempts, open inbox items, spending so far |
| `runner inbox [--for planner\|human]` | anyone | Lists open inbox items |
| `runner pause [--now]` | human | Stops starting attempts; with `--now`, also interrupts running ones (D52) |
| `runner resume` | human | Applies changes made meanwhile and continues interrupted attempts (D52) |
| `runner login claude-code\|codex` | human | Logs in to the agent tool once, into the campaign's own login folder (D88) |
| `runner submit <entry.toml> <file.lean>` | Planner | Adds a graph entry with its stub or definition file (D26) |
| `runner revise <id> [<entry.toml>] [<file.lean>]` | Planner | Changes an entry; triggers the re-check of section 11 (D53) |
| `runner withdraw <id>` | Planner | Removes an entry nobody depends on |
| `runner resolve <item-id> [--note <text>]` | Planner, human | Closes an inbox item |
| `runner approve <target-id>...` | human | Approves top-level statements, and applies held changes to the files they cover; creates or moves the approval tag (D20, D69) |
| `runner heartbeat-pass` | human | Runs the end-of-campaign heartbeat pass (D23) |
| `lean-verify <repo> <commit>` | anyone | Independent check (section 12.3); a separate program |

## 6. The Prover

### 6.1 The packet

Every attempt, whatever the implementation, receives:

- the task's stub (the statements to prove) and the Planner's `notes`;
- for each name in `lemmas`, its full statement (looked up in the index or Mathlib);
- one line for each module in `depends`: its name and module docstring (D78);
- the time limit and how much remains;
- after a failed check or a re-check: the previous proof and the diagnostics.

The packet is also saved as `/work/PACKET.md`, so an agent-tool Prover can re-read it after its context is compacted. The full table of contents, one line per accepted module, is the file `/work/TOC.md`, read only when needed (D78).

### 6.2 Tools

| Tool | Does |
|---|---|
| `read_file(path, start?, end?)` | Reads a project or dependency Lean source, or the entry's notes |
| `write_task_file(content)` | Replaces the task file (only the task's own file is writable) |
| `edit_task_file(old, new)` | Replaces one unique piece of the task file |
| Lean server tools | Goal and term-goal at a position, hover, completions, diagnostics, file outline, declaration location, local search, run a snippet, try several tactics, references: as in Baker's runner |
| `search_index(query)` | Matching lines from the project's lemma index (section 6.4) |
| `loogle(query)` | Search Mathlib by type pattern: one Loogle process on the host, run by the Runner against the pinned Mathlib, offline (D54, D79) |
| `leansearch(query)` | Search Mathlib by meaning: the remote LeanSearch service, called by the Runner; results whose names are not in the pinned Mathlib are dropped (D79) |
| `check()` | Asks for the acceptance check; ends the Prover's turn (D43). Only the task file counts: if other files in the workspace changed, the result says so and that they were ignored (D80) |

A model-API Prover gets these as tool definitions. An agent-tool Prover gets the Lean server tools from a Lean server in its sandbox, and the Runner-provided tools (`search_index`, `loogle`, `leansearch`, `check`) through a small MCP server in the sandbox that forwards to the Runner over a Unix socket mounted into the sandbox. Its own file tools replace `read_file`, `write_task_file` and `edit_task_file`, limited by the sandbox (D64).

### 6.3 Attempt lifecycle

1. The Runner creates the attempt's workspace: the campaign commit plus the task file; the dependency packages and the shared build cache are mounted read-only.
2. It starts the Prover: the model-API loop, or the agent tool through its adapter, inside the sandbox.
3. On `check()`: the attempt sandbox is stopped completely; the check runs (section 7) in the attempt's own slot, so it never waits in a queue (D81). Pass: done. Fail: a fresh sandbox on the same workspace; the Prover resumes with the diagnostics and the remaining time (the model-API loop appends a message; an agent tool resumes its session through the adapter). There is no limit on the number of checks; the time limit is the only limit.
4. At the time limit the Runner stops the attempt. A check that has already started finishes first (D81). The attempt then ends without a pass, and the Fixer is called (D34).
5. **Usage limits** (D81): if an agent tool reports that its subscription's usage limit is reached, the attempt becomes `interrupted`, not failed. Its clock stops, no new attempts start for that tool, and a `usage-limit` item goes to the human. Attempts continue when the limit resets.
6. The Prover's final message, if it is blocked, states the obstacle precisely (section 9).

Time counts from the attempt's start, including tools and checks; it is written to `attempt.json` every few seconds (D52).

### 6.4 The lemma index

After each acceptance, definition entries included, the Runner writes a line to `index.jsonl` for each public declaration of the entry: full name, statement (pretty-printed, cut at a fixed length), module, first line of its docstring. When an entry is accepted again, after a re-check, its old lines are replaced (D82).

`search_index` returns at most 20 matching lines. It matches query words against the name (split into words at `_` and `.`), the statement and the docstring, and ranks lines by how many query words they match (D82).

## 7. The acceptance check

Runs in its own sandbox, offline, on a fresh copy of the current campaign commit plus the submitted file (D76). Steps:

1. **Static scan** of the submitted file, ignoring comments and strings. Each rejection names the line and the rule (D75). It rejects:
   - **limits raised beyond one declaration** (D23, D75): `maxHeartbeats`, `maxRecDepth` and `synthInstance.maxHeartbeats` may be set only as `set_option … N in` directly before one declaration, and never to `0`;
   - **other settings** (D72): any `set_option` outside the allowed list: the three limits, `autoImplicit`, `relaxedAutoImplicit`, `linter.*`, `pp.*` and `trace.*`. This rejects, for example, `debug.skipKernelTC`, which turns off the kernel's check;
   - **code that runs while the file is compiled or imported** (D72): `#eval` (and variants such as `#eval!`), `run_cmd`, `run_tac`, `run_elab`, `by_elab`, `initialize`, `elab`, and the `unsafe`, `implemented_by` and `extern` keywords. Files listed in `check.allow_code` are exempt; only the human adds to that list;
   - **in task and rewrite files only** (D15, D74): global `instance`, `@[simp]`, `notation`, `infix`, `macro`, `syntax` and `attribute [...]` without `local` or `scoped`.
2. **Build** the module with `lake build`, within `check_time_limit`.
3. **Audit,** in Lean:
   - each name in `statements` exists inside the entry's namespace and is a theorem;
   - its type is definitionally equal to the stub's statement. The stub is compiled under a separate namespace for the comparison, as in Baker's audit;
   - **every declaration in the module** uses only the axioms `propext`, `Classical.choice` and `Quot.sound`, collected transitively (D73). `sorry` shows up as the axiom `sorryAx`, and `native_decide` as `Lean.ofReduceBool`, so this rule rejects both.
4. **Module checks:**
   - every public declaration of the module starts with its namespace;
   - its imports satisfy section 3.2.

**Definition files** (D74) go through the same steps, except that global instances, `@[simp]` and notation are allowed, and there are no statements to compare.

Deprecation warnings are ignored (D21).

**Committing results** (D76): the Runner commits accepted results one at a time. If a file the entry imports, directly or indirectly, changed between `checked_on` and the commit, the check runs again on the new commit.

**Limits of the scan:** it is a text scan, a cheap first line of defence but not watertight. `lean-verify` must not rely on it (section 12.3).

**Receipt** (`receipts/<id>.json`), committed with the accepted file (D77):

```json
{
  "id": "heights.bounds",
  "checked_on": "<campaign commit the check ran on>",
  "file": "<Git blob id of the accepted file>",
  "runner_version": "<protocol repository tag>",
  "attempts": [
    {"id": "<attempt-id>", "role": "prover", "implementation": "claude-code", "tool_version": "<version>", "model": "<model id>",
     "started_on": "<campaign commit>", "seconds": 1800, "outcome": "time-limit"},
    {"id": "<attempt-id>", "role": "fixer", "implementation": "codex", "tool_version": "<version>", "model": "<model id>",
     "started_on": "<campaign commit>", "seconds": 412, "outcome": "passed"}
  ],
  "imports": ["Baker.Heights.Basic", "Mathlib.Algebra.Order.BigOperators.GroupWithZero.Finset"],
  "axioms": ["propext", "Classical.choice", "Quot.sound"],
  "limit_raises": [{"declaration": "height_bound", "option": "maxHeartbeats", "value": 400000}],
  "accepted_at": "2026-11-02T14:03:11Z"
}
```

- `implementation` is `claude-code`, `codex` or `model-api`; `tool_version` is the agent tool's version, empty for `model-api` (D95).
- `outcome` is `passed`, `time-limit`, `split` or `escalated`. An interrupted attempt continues under the same id.
- `started_on` fixes the prompt versions the attempt used, since the prompts are in the repository. The Lean and Mathlib versions are in `checked_on`.
- A file with no attempts was written by the Planner.

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

- **After a split** (D83): the new entries are added to the original task's `depends`, so it is `waiting`. When they are proved, the Runner checks the saved candidate first, without an agent. Pass: `proved`. Fail: `can-be-attempted`, starting from the candidate and the diagnostics, as after a re-check.
- **After a usage limit** (D84): the Runner resumes one interrupted attempt at the reset time the agent tool reported, or every 30 minutes if it reported none. If that attempt runs, the others follow.
- **Interrupted checks** are simply run again; the check is deterministic (D85).
- **A task the Planner revises after it went `with-planner`** gets a fresh Prover attempt, and a fresh Fixer if that fails (D85).

`state.json` holds every entry's status, its current attempt and its time used. It is rewritten atomically: write a new file, then rename it.

**Crash recovery** (D52): on start, the Runner reads `state.json`, removes leftover sandboxes, marks entries that were `proving`, `fixing` or `checking` as `interrupted`, starts paused, and posts an inbox item for the human.

## 9. Prompts

The campaign's prompts live in `prompts/`, copied from the protocol repository's defaults at setup, and may change during a campaign (D50). An attempt's `started_on` commit records which version it used (D77).

- **Plain Markdown, no placeholders** (D86). Everything task-specific is in the packet.
- **How a prompt reaches its role** (D86): for an agent tool, the adapter installs it as the instruction file the tool re-reads by itself (`CLAUDE.md` for Claude Code, `AGENTS.md` for Codex) at the workspace root, so the rules survive context compaction. For a model-API role, it is the system prompt of every request.
- **Nothing else reaches the agents** (D88): agent tools run with the campaign's own login folder (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`), which holds only the login. The human's personal instructions, memory, settings, hooks and plugins are never mounted.

Files:

- `prompts/prover.md`: the Prover's rules (checklist in `DESIGN.md` §16).
- `prompts/prover-rewrite.md`: for the optional rewrite (D59).
- `prompts/fixer.md`: the Fixer's rules.
- **The Planner's** instruction file (`CLAUDE.md` or `AGENTS.md`) and start prompt live in the Planner's own working folder, outside the campaign repository and its clones (C9).

## 10. The Fixer and the inbox

### 10.1 What the Fixer receives (D44)

A copy of the Prover's workspace, the packet, the last check's diagnostics, the Prover's final message, and the path of the Prover's transcript. Its tools are the Prover's, `check()` included, plus `report()` (10.2).

### 10.2 How the Fixer ends (D87)

- **Finish:** a passing `check()` ends the Fixer, exactly as for the Prover.
- **Split or escalate:** the Fixer calls `report()` with one of:

```json
{"outcome": "split", "summary": "...",
 "new_entries": [{"entry": "<TOML text of graph/<id>.toml>", "stub": "<Lean text>"}]}
{"outcome": "escalate", "summary": "...", "reason": "false" | "needs-change" | "other",
 "affected": ["<task ids>"], "proposed_statement": "<optional Lean text>"}
```

  For a split, the candidate proof of the original task is the task file as it stands.
- **Validation on the spot:** the Runner checks the report at once, the four guards of D13 included, and returns any problem to the Fixer as a tool error while it still has time. For guard 3 it runs `exact?` briefly on each new statement, with all accepted modules imported; if that finds a proof, the report is refused with the lemma's name, so the Fixer can use it (D89).
- **A valid split:** the Runner adds the new entries (`created_by = "fixer"`, `parent` set), keeps the candidate as the original task's saved proof (section 8), and records an inbox notice for the Planner.
- **A valid escalation** sends the task to the Planner; for a top-level statement, also to the human.
- **Time limit** with neither a pass nor a valid report: `failed-after-fixer`, to the Planner.

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
   - **Unproved entries too** (D90): stubs of entries not yet proved that depend on the change, directly or not, are compiled again. A stub that no longer compiles goes to the Planner (`with-planner`), since its change broke it.
2. **Cancel** attempts running on affected entries. They don't count as failures.
3. **Mark** affected entries `needs-recheck`.
4. **Re-check,** in dependency order, in free slots and before any new attempt starts (D91): run the acceptance check on each entry's existing file against the current stubs.
   - Pass: a new receipt, `proved`.
   - Fail: the entry becomes `can-be-attempted` once its dependencies are proved, and the Prover starts from the previous proof and the new diagnostics.

A change to the Lean or Mathlib version re-checks every entry, after a full rebuild.

## 12. Sandboxes, network, setup check and `verify`

### 12.1 Sandboxes (D17, D18, D64, D95)

Every attempt and every check runs in its own sandbox: `bubblewrap` decides what the processes can see, inside a `systemd-run --user --scope` that holds their memory. There is no container engine and no image.

- **What a sandbox sees:**
  - the host's system folders (`/usr`, `/etc` and the like), read-only. Home folders, `/run`, `/var` and other campaigns are hidden;
  - `/work`: the attempt's workspace, the only writable folder;
  - the pinned Lean toolchain and the dependency packages (Mathlib and its dependencies), read-only;
  - the shared build cache of proved entries, read-only, with a private writable overlay;
  - `/runner.sock`: the Runner tools socket (section 6.2);
  - agent sandboxes only: the agent tool's program, the campaign's login folder for that tool (D88), and the proxy socket (12.2).
- **Processes:** the sandbox has its own process namespace. Stopping its scope ends every process in it, Lean server included (D43).
- **Memory:** `MemoryMax` from `campaign.toml`, and `MemorySwapMax=0`. A slot holds one sandbox at a time.
- **Setup instead of an image:** Lean through elan, as pinned by `lean-toolchain`; Mathlib as pinned by `lake-manifest.json`, fetched once; Loogle and the list of Mathlib names, made once; Claude Code and Codex installed once per campaign at fixed versions, into a read-only tools folder, with self-updating off. Receipts record the agent tool's version (D77); the Lean and Mathlib versions follow from the commit.
- **Agent tools** run with their own permission prompts and sandboxing off: nobody answers prompts in a non-interactive run, and the protocol's sandbox is the boundary (D64).

### 12.2 Network (D54, D96)

- Every sandbox has an empty network namespace: no network, only its own loopback.
- **Model-API attempts and checks** need nothing more: the Runner makes the model calls and searches from the host.
- **Agent sandboxes:** the filtering proxy runs on the host. It is tinyproxy, denying every host except `network.provider_hosts`. Its port is bridged to a Unix socket, which is mounted into the sandbox and exposed on the sandbox's loopback by `socat`; `HTTPS_PROXY` points there.
- **Web search run at the provider's end** (Claude's and Codex's own web search) cannot be blocked by the proxy, so the adapter switches it off, and `setup-check` confirms it.

### 12.3 `lean-verify` (D19, D92)

A separate program, independent of the Runner and short enough to read: a thin wrapper around Lean's own judge, `lake comparator` (part of Lake since Lean v4.35.0). It runs on the host with the pinned toolchain; the comparator brings its own sandbox. Given a campaign repository and a commit:

1. it makes a clean checkout;
2. it checks, with Git, that every file the approval covers is unchanged since the approval tag (D69, D93);
3. it fetches the pinned dependencies and Mathlib's published build cache. This is the only step with network. Building Mathlib from source instead avoids trusting the published cache for the meaning of Mathlib's definitions, as the comparator's documentation notes;
4. it writes the comparator's inputs: a challenge module made from the approved stubs, a solution module importing the top-level modules, and a configuration naming the top-level theorems, with the permitted axioms `propext`, `Classical.choice` and `Quot.sound`;
5. it runs `lake comparator --paranoid`. Inside the comparator's sandbox, without network, the project is built and exported, and each top-level theorem is replayed through Lean's kernel and the independent checkers bundled with Lean. None of the project's compiled files is loaded into the judge, so the project's code cannot influence the verdict;
6. it prints a report, listing under each top-level theorem the assumptions in its statement (D70), and exits non-zero on any failure.

### 12.4 The comparator per task (D94)

The pilot measures how long `lake comparator` takes per task; it replays every Mathlib lemma a task depends on. If it is fast enough, it replaces the audit of section 7, step 3: the scan stays, and the comparator does the rest.

### 12.5 `setup-check` (D97)

- Confirms that bubblewrap (0.8 or later, with unprivileged user namespaces) and systemd scopes with cgroup v2 work, and that the memory cap holds.
- Builds a tiny Lean file in a sandbox.
- Runs the acceptance check on a good file and on bad files: a wrong statement, a forbidden axiom, `sorry` in an unused helper, `native_decide`, a file-wide heartbeat setting, a setting outside the allowed list, a command that runs code, a global instance, a public declaration outside the namespace.
- Runs `lake comparator` on a good and a bad example.
- Makes one request per configured role.
- For agent tools: confirms that the agent cannot read or write outside its workspace, reach a host outside `provider_hosts`, or use web search, and that two sandboxes can share one login.
- Runs `lean-verify` on the result.

## 13. Lessons file

`lessons.md`, one section per lesson:

```markdown
## 2026-11-02 · Short title
**Lesson:** what was learned.
**Evidence:** tasks, receipts or logs.
**Suggested change:** to the Runner, prompts, settings or planning, if any.
```

## 14. Review of draft 0.1

All settled. Batch 1: 2.1 (D65), 3.1 (D66), 5.1 (D67). Conditional formalisations: D68–D71. Batch 2, the acceptance check: D72–D77. Batch 3, the Prover: D78–D82. Batch 4, statuses, prompts and the Fixer: D83–D89. Batch 5, re-check, sandboxes and `verify`: D90–D97. Raised while writing `lean-verify`: D98 (what stubs may import).
