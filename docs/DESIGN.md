# Lean formalisation protocol v2: design reference

Agreed 2026-10-27. This file describes the design as decided. The full history, rejected options and the Baker evidence behind each choice are in `DECISIONS.md`.

## 1. Principles

- **Agents write proofs; a small deterministic checker decides what is accepted; you own the top-level statements and the infrastructure.**
- **Minimal overhead:** Git keeps the record, the Linux kernel enforces resource limits, and all state lives in files on disk. Lessons become automatic checks wherever possible, rather than instructions to remember.
- **No speculation:** nothing is ever built on a result that is not yet proved.
- **Change is allowed.** Only the Runner's program stays fixed during a campaign. Anything else can be changed, and the Runner works out what has to be re-checked, so a change in the middle never breaks the campaign.

## 2. Participants

| Role | What it is | Job |
|---|---|---|
| **You (the human)** | | Confirm the campaign configuration. Approve each top-level statement. Fix infrastructure problems the Runner cannot solve, alone or with the Planner's help. Pause, change and resume the campaign whenever you want. Decide escalated top-level statements. Decide whether, and by whom, the project is rewritten after the campaign. |
| **Planner** | One long-lived agent session, on any machine that can reach the Linux host, with full access to that host | Sets up the campaign. Writes the definitions and task statements, maintains the dependency graph, sizes tasks, and handles Fixer outcomes and escalations. Keeps the lessons file. Trusted by you: works directly on the host, runs its own Lean checks and may start worker agents, for example to gauge how hard a task is, without going through the Runner. May assist you at any time, including with infrastructure, but never changes the Runner's program. |
| **Runner** | A deterministic program, no model | Schedules tasks, runs containers and checks, writes receipts, keeps the lemma index and the inbox, handles routine infrastructure faults, re-checks after changes, writes summaries. |
| **Prover** | Either a model driven by the Runner through a model API, or an agent tool (Claude Code or Codex) started by the Runner, as agreed in the configuration | Makes one attempt per task. |
| **Fixer** | Either an agent tool (Claude Code or Codex) started by the Runner, or a model driven by the Runner through a model API, as agreed in the configuration (called the Repairer in Baker) | Called after one failed Prover attempt; finishes the proof, splits the task, or escalates. |

Provers and Fixers never message anyone. Only one Planner session runs at a time.

## 3. Project structure

- **Definition files** are written by the Planner, together with any instances the definitions need. Each is checked to compile.
- **Task files: one per task.** A task is a logically coherent piece of work that the Prover should pass on its first attempt within the time limit. It may contain several theorems. The Planner writes each theorem as a stub: the full statement with a `sorry` proof. That stub is the task's current statement. Task files contain only theorems and helper lemmas, never definitions.
- **Basic lemmas about a definition.** The Planner may write very simple proofs about its definitions that it expects to be needed often but that are too small to be a task. Examples are lemmas that hold by definition, or facts like "`fieldKind` is 1 or 2", which Baker's Provers re-proved privately in 6 files. These are recorded as written by the Planner. Anything that needs real thought is a task for a Prover.
- **Namespaces:** everything public in a task file lives in that task's own namespace. Helper lemmas are public by default, so later tasks can reuse them. Task files may not change anything globally: instances, `@[simp]`, notation and attribute changes must be `local` or `scoped`.
- **Imports:** a task may import any proved task, and never an unproved one. Lean imports whole files, so a task waits until *every* theorem in each file it imports is proved. The Planner groups theorems with this in mind.
- **Top-level statements** each come with a target sheet: a plain-language explanation, using Baker's `TARGET.md` template.
- **Receipts** (records of passed checks) are small files committed to the repository.

## 4. The dependency graph and scheduling

- **All tasks live in one dependency graph**, which the Planner extends while the Runner works. A task **can be attempted** once every task it uses is proved. It then starts as soon as one of the N attempt slots is free.
- **How many run at once:** the number of tasks that can be attempted, up to N. The Runner shows both numbers live, together with the **depth** of the dependency graph: the longest chain of tasks that each need the one before. The depth sets how long proving must take at least, so the Planner tries to keep it small.
- **Adding tasks while running.** The Planner submits new tasks with a command. The Runner checks that their statements compile and that they create no cycles, then adds them at once. The Planner tries to keep at least N tasks that can be attempted. Changing existing tasks is covered in section 12.
- **Task size:**
  - The Planner writes no difficult tasks. It splits a difficult argument into more tasks rather than proving it itself.
  - It learns from the Runner's report on each task: attempts, time used, Fixer calls, heartbeat raises. It may also run its own Lean checks or trial agents to gauge difficulty. There is no numeric target.
  - Two things to balance. Tasks must be made easy by splitting, not by the Planner doing the central proofs. And every extra task costs a packet, a compile and a check, while long chains of tasks increase the depth.

## 5. The life of a task

1. **Prover attempt.** Once the task can be attempted, the Runner starts a Prover in its own container.
   - The Prover's packet contains the statements to prove, the Planner's short list of relevant lemmas (names and statements, no proofs) and a one-line-per-file table of contents.
   - Everything else the Prover finds on demand: search over the project's lemma index, `exact?`, Loogle, reading files. It tries `exact?` before writing a helper.
   - The Prover's rules are sent with every request, so they can't be forgotten. An agent-tool Prover gets the same packet, tools and rules, through its prompt, its workspace and a rules file.
2. **Check.** When the Prover asks for its check, its container is stopped completely, Lean server included. The check runs in a separate container, on the project's accepted sources plus the submitted file.
   - **Pass:** the task is proved and a receipt is committed.
   - **Fail:** a fresh container on the same workspace lets the Prover carry on, with the check's diagnostics and its remaining time. Time spent checking counts against the time limit.
3. **What the check requires:**
   - every theorem's statement is exactly the task's current statement;
   - the only axioms used are `propext`, `Classical.choice` and `Quot.sound`;
   - no `sorry` in the task's own proofs;
   - imports of proved tasks only;
   - the namespace rule, and no global changes;
   - heartbeat raises only for single declarations: no file-wide setting and no unlimited setting.

   Warnings about deprecated names are ignored.
4. **Fixer.** If the attempt ends without passing, the Fixer is called, once. It gets:
   - a copy of the Prover's whole workspace;
   - the packet, the last check's diagnostics, and the Prover's final message explaining what blocked it;
   - the Prover's full transcript on disk, to read if useful.

   It starts a fresh conversation, with its own time limit. A Fixer attempt takes up one of the N slots.
5. **What the Fixer can do:**
   - **Finish:** its proof goes to the check.
   - **Split, one level only:** it adds new tasks (as stub statements) and saves a proof of the original task that uses them. You and the Planner don't approve splits; the Planner is notified. Before accepting a split, the Runner checks that:
     1. the original statements are unchanged, the new ones compile, and there are no cycles;
     2. the saved proof compiles against the new stubs and has no `sorry` of its own;
     3. any new statement that matches an already-proved theorem is replaced by that theorem;
     4. the new tasks sit next to the original.

     The saved proof is checked properly once the new tasks are proved. When writing new statements, the Fixer follows the Planner's rules for statements. A task created by a split that would need splitting again goes to the Planner.
   - **Escalate:** the statement looks false or needs to change. It goes to the Planner, and to you if it is a top-level statement. A fix that would change another task's statement, or a definition, is always an escalation, never a split.
   - **No success:** if the Fixer's proof fails the check, or the Fixer ends without a proof or a split, the task goes to the Planner.

## 6. Rules for Lean code

- **Heartbeats** (Lean's per-declaration work limit):
  - `set_option maxHeartbeats N in` is allowed only directly before a single declaration, with no fixed maximum.
  - At the end, every raise is removed in turn and the project rebuilt; only raises that are actually needed are kept.
  - **Guidance for the Planner:** one main idea per expected proof; separate named theorems rather than long conjunctions; basic lemmas for each definition; one number system per statement where the mathematics allows; large numerical facts in their own tasks.
  - **Guidance for the Prover:** if a declaration runs out of heartbeats, split it before raising the limit; prefer `simp only [...]` and `linarith only [...]`.
- **Helper lemmas** are public by default, in the task's namespace.
- **Deprecated names** are tolerated during the campaign. They are fixed in the optional rewrite, if Lean and Mathlib are upgraded.

## 7. Trust and records

- **The acceptance check** is the same as in Baker: exact statements plus the allowed axioms.
- **`verify`** re-checks a finished project independently. It works from a clean copy of a commit, in the pinned environment, offline, and without any agents. It rebuilds everything and re-checks every top-level theorem's exact statement and axioms.
- **Receipts** record:
  - the commit, the Lean version, the container image and the Runner version;
  - the prompt versions used;
  - the result;
  - who wrote each file: Prover, Fixer or Planner.

  Git keeps everything tamper-evident, so no separate checksums are needed.
- **Top-level statements:**
  - you approve each one from its target sheet, and your approval is recorded as a Git tag;
  - the Runner refuses any change to an approved statement without a new approval from you. Provers still fill in the proofs;
  - the tag lives on the host. Accepted risk: a Planner with full host access could move it.
- **Trusting the Planner does not change what counts as proved:** only the Runner's check accepts a proof, whoever wrote it.
- **What the guarantee covers:** Lean guarantees that the statements are proved, not that they say what you intended. That is what the target sheets and your approval are for.

## 8. Environment and resources

- **Host:** always Linux.
- **Containers:** every Prover attempt, every check and every Fixer's Lean work runs in its own short-lived container (Docker or Podman), all from one image with the pinned Lean, the Mathlib build and the Lean server tools.
  - Only the attempt's own workspace is writable.
  - Mathlib is shared read-only between containers.
  - Compiled files of proved tasks come read-only from one shared cache kept by the Runner, which grows as tasks are accepted. Each container adds a private layer for its own outputs.
- **Network:** containers have no network access. The Runner carries out the Prover's Loogle and LeanSearch calls itself, outside the container; this costs no extra tokens.
- **Agent tools and logins:** a Prover or Fixer that is an agent tool runs on the host, started by the Runner and logged in there with your subscription, so no credentials ever enter a container. The tool's own sandbox limits it to its workspace, its Lean work runs in its container, and its own web tools are turned off; searches go through the Runner. The host has internet access, for model calls and searches.
- **Lean servers:** one per attempt, never shared.
- **Resources.** The numbers are set from a measurement at setup.
  - At most N attempts run at once.
  - Each container has a memory cap, with swap off.
  - An attempt and its check never run at the same time, so a slot holds one container at a time.
  - Running out of memory is reported to the Prover like any other tool error, and never stops the campaign.
  - With subscription logins, the plan's usage limits also cap how many attempts can usefully run at once. Hitting a limit stops new attempts until it resets; nothing is lost.
  - The Planner's own Lean checks and worker agents run outside this limit, so N and the memory cap should leave room for them.
- **Versions:** Lean and Mathlib normally stay the same throughout. They can be changed at a pause, at the cost of a full rebuild and re-check (section 12).

## 9. Configuration and setup

- **One-step configuration.** At the start, the Planner proposes the whole configuration in one message:
  - how the Prover and the Fixer are implemented: through a model API, or as an agent tool (Claude Code or Codex) with your subscription;
  - the model and reasoning setting for Planner, Prover and Fixer;
  - the attempt time limits;
  - N and the memory cap;
  - any spending or time cap, which also covers the Planner's worker agents;
  - how often you want a summary.

  You confirm it or change items. Nothing that costs money is chosen silently. You can change any of it later (section 12).
- **`setup-check`** runs on a new host before any campaign. It compiles a tiny Lean file in the image, runs the acceptance check on a good and a bad file, confirms the memory cap works, makes one model request per role, and runs `verify`.

## 10. Monitoring and the Planner session

- **The Runner does all the monitoring.** It writes an event log and an inbox of items that need a decision.
  - Mathematical items go to the Planner: escalations, too few tasks that can be attempted, completion. Fixer splits are recorded for the Planner to review.
  - Infrastructure items go to you.
  - Nobody polls on a timer.
  - You get a short summary, written by the Runner, as often as you chose, by email, chat message or desktop notification.
- **The Planner is one long session**, relying on its tool's automatic compaction, and checks the inbox between pieces of work. Safeguards:
  1. the files on disk are the truth, and the Planner re-reads them rather than relying on memory;
  2. its rules live in the instruction file its tool loads automatically (`CLAUDE.md` or `AGENTS.md`), kept outside the project folder so that Fixers don't pick it up; the Fixer has its own rules file;
  3. you are alerted if the inbox goes unread for too long. Restarting the Planner just means starting a new session with the standard prompt.

## 11. Pausing, interruptions and recovery

The same mechanism covers a deliberate pause, an infrastructure problem and a crash.

- **`pause`:** no new attempts start, and running attempts carry on to their end. The Planner can keep working, and you can make changes.
- **`pause --now`:** running attempts are also stopped at once and marked *interrupted*, with the time they have used recorded.
- **`resume`:** every change made in the meantime takes effect. Each interrupted attempt carries on with its remaining time, in the same workspace and conversation. An attempt is restarted from scratch only if its model never ran.
- **A crash or reboot** counts as an unplanned `pause --now`. When the Runner starts again, it rebuilds its state from disk, clears leftover containers and marks the attempts that were running as interrupted. Then you run `resume`. It never resumes by itself, so a recurring fault can't make it restart over and over.
- **Little is lost.** The Runner writes each attempt's time used to disk every few seconds.
- **An interrupted Fixer** continues through its tool's own session-resume feature where available. Otherwise it restarts on the same workspace with its remaining time, and the interrupted transcript is available to it.
- **No interruption ever uses up a Prover or Fixer attempt.**

**Infrastructure problems:**

1. **The Runner handles routine faults itself.** It retries a temporary provider error after a pause, within the same attempt; restarts a crashed Lean server and tells the Prover; and retries a failed container start once.
2. **Otherwise it judges how far the problem reaches.** A problem with one attempt pauses only that task. A problem with the whole host (disk, image, Docker, Git) or the model provider (login, quota, outage) stops new attempts, while unaffected running attempts continue.
3. **It keeps everything:** workspace, transcript, logs and time used. The task is marked *interrupted*, not failed.
4. **It tells you** what failed, how far it reaches, where the evidence is, and what it already tried.
5. **You fix the problem, alone or with the Planner's help, and run `resume`.**
6. **Repeated failures** of the same kind always come to you; nothing is retried forever.

**A bug in the Runner itself** is different. Its program cannot be changed during a campaign, so a blocking Runner bug ends the campaign. The fix is part of a protocol revision afterwards, and continuing the work is a new campaign on the same project.

## 12. Changing things during a campaign

Only the Runner's program is fixed. Everything else may change, and the Runner works out the consequences.

- **Settings, prompts, the Planner's rules, and tools in the container image** take effect for attempts that start afterwards. Receipts record which versions were used.
- **A task's statement, or a definition**, may change at any time. Top-level statements also need your new approval. When one changes:
  1. any attempt running on an affected task is cancelled, without counting as a failure;
  2. the changed task, and every task depending on it, loses its proved status;
  3. the Runner re-checks the existing proofs against the new statements, automatically and without agents;
  4. only the proofs that now fail go back to "can be attempted". The Prover then starts from the old proof and the new diagnostics.

  A small change therefore costs only the re-checks it actually needs.
- **Removing a task that others use** is refused until those tasks are changed too.
- **Lean or Mathlib versions** may change at a pause. The cost is a full rebuild and the same automatic re-check of every task.

## 13. End of campaign

1. **All top-level statements are proved.**
2. **Heartbeat pass:** the Runner removes each heartbeat raise in turn, rebuilds, and keeps only the raises that are needed.
3. **`verify`** on the final commit. The verified commit is the campaign's certified result.

**Optional rewrite afterwards.** You may later have the project rewritten for quality: organised by topic, renamed, duplicates merged, long proofs split, and Lean and Mathlib optionally upgraded. You decide whether and when, and who does it: the Planner, or a new agent started from your own machine. The job, and what it must take into account, are described in `REFORM.md`, which can be handed to that agent as it is.

## 14. Commands

| Command | Used by | Purpose |
|---|---|---|
| `setup-check` | You or the Planner, at setup | Check a new host |
| `run`, `status` | You, the Planner | Start the Runner; show progress, the inbox, how many tasks can be attempted, and the depth |
| `pause`, `pause --now`, `resume` | You | Pause the campaign, softly or at once; continue it, after changes or an infrastructure fix |
| `submit`, `revise`, `withdraw`, `resolve` | Planner | Add tasks; change or remove tasks; close inbox items |
| `approve` | You | Approve top-level statements |
| `verify` | Anyone | Independently re-check a commit |

## 15. Implementation

- **The Runner is written new**, reusing two proven parts of Baker's runner: the acceptance check, and the loop that drives the Prover (model calls, Lean tools, file editing).
- **Adapters** for Claude Code and Codex let the Runner start a Prover or a Fixer as an agent tool: the command line and model, the sandbox limiting it to its workspace, routing its Lean work into the container, resuming a session, reading its result. Their exact options are checked at setup.
- **The model-API loop** supports both chat completions (DeepSeek, OpenRouter, local servers) and Anthropic's own API.
- **The Planner** needs no adapter: you start it yourself, in any agent tool, with its instruction file and a start prompt.
- **Tests:** unit tests with tiny Lean files, including scripted end-to-end tests that replay recorded model responses: adopting a split, re-checking after a split, resuming after an interruption, adding tasks while running.
- **No example project** is shipped.
- **Still to build:**
  - the lemma index and its search tool;
  - pause, resume and crash recovery;
  - the automatic re-check after a change;
  - `setup-check`;
  - the Runner carrying out the Prover's search calls;
  - keeping the Planner's instruction file out of attempt workspaces.

## 16. What the role prompts must say

- **Planner:**
  - propose the whole configuration in one message;
  - write a target sheet for each top-level statement;
  - write the definitions, plus very simple, often-needed proofs about them that are too small to be tasks;
  - write no difficult tasks: split rather than prove central arguments itself; learn from the Runner's report on each task;
  - statements: one main idea per expected proof, separate named theorems rather than long conjunctions, one number system per statement where possible, large numerical facts in their own tasks;
  - put in one file only theorems that are needed together; keep the depth small; keep at least N tasks that can be attempted;
  - trust the files on disk, not memory;
  - read and add to the lessons file;
  - never change the Runner's program;
  - it may run its own Lean checks and start worker agents to calibrate difficulty; their results are not accepted proofs.
- **Prover:**
  - search before writing; try `exact?` before writing a helper;
  - helpers public in the task's namespace; no global changes;
  - if a declaration runs out of heartbeats, split it first; prefer `simp only` and `linarith only`; raise heartbeats only for a single declaration;
  - save useful partial work in the task file;
  - stop as soon as the check passes; if blocked, end by stating the obstacle precisely, because the Fixer starts from that message.
- **Fixer:**
  - start from the inherited workspace, the diagnostics, the Prover's final message and, if useful, its transcript;
  - finish, split one level, or escalate; never change another task's statement or a definition;
  - write new statements by the Planner's rules.
- **Prover, on a rewrite task** (used if the optional rewrite runs through the Runner):
  - rewrite the file following the plan, keeping every statement's meaning;
  - prove that each renamed or restated top-level theorem gives the approved statement.

The optional rewrite after the campaign has its own brief, `REFORM.md`.

The prompts themselves can be improved during a campaign (section 12).

## 17. Lessons and protocol revision

- **The lessons file.** The protocol comes with a lessons file from earlier campaigns, which the Planner reads and uses.
  - During a campaign, the Planner and you add entries to the campaign's copy, kept in the project repository. Each entry gives the lesson, the evidence (tasks, receipts, logs) and any suggested change to the protocol.
  - Lessons about planning, prompts or settings can be acted on during the campaign: the Planner through its own planning, and you (with the Planner's help if you like) by changing prompts or settings.
  - Changes to the Runner's program, including its checks, wait for the revision after the campaign. There, you and a revision agent merge the entries into the protocol's lessons file and turn them into automatic checks wherever possible.

## 18. What v2 drops from Baker's protocol

- Stages and batches.
- Conditional claims, `Work` wrappers, assemblers and completion files.
- Sending a repaired task back to the Prover.
- Private-by-default helpers.
- Imports limited to declared dependencies.
- Whole earlier proofs pasted into packets.
- File-wide heartbeat raises.
- Timed observation rounds.
- Custom process tracking and isolation wrappers.
- Separate checksum files.
- Stopping the Runner to add new work.
- Frozen specification files: changes now trigger targeted re-checks instead.

## Glossary

- **Task:** one unit of proof work: one file with one or more statements and their proofs. All tasks live in the dependency graph of all tasks.
- **Dependency graph:** which tasks use which; a task can only use tasks that come before it.
- **Can be attempted:** a task whose dependencies are all proved, so a Prover can start on it.
- **Depth:** the longest chain of tasks that each need the one before; it sets the minimum proving time.
- **Stub:** a theorem with a `sorry` proof, written by the Planner as a task's current statement.
- **Approved statement:** a top-level statement you have approved; changing it needs your approval again.
- **Interrupted:** an attempt stopped by a pause, a crash or an infrastructure problem; it carries on later with its remaining time.
- **Packet:** what a Prover receives at the start of an attempt.
- **Slot, N:** one running attempt; N is the most that run at once.
- **Inbox:** the list of items waiting for a decision, by the Planner or by you.
- **Receipt:** the committed record of a passed check.
- **Target sheet:** a plain-language explanation of a top-level statement, for your approval.
- **Lessons file:** the record of lessons, kept by the Planner and you during a campaign, and used to revise the protocol afterwards.
