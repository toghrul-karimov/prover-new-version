# Lean campaign protocol v2: design decisions

Started 2026-10-27. Status: **Decided**, **Open**, **Closed** (no longer applies), or **Consequence** (follows from a decision; still to resolve).

## Decided

| ID | Decision | Date |
|---|---|---|
| D1 | Participants: Planner, Runner, Prover, Fixer, Reformer. *Amended by D56 and D57: there is no Reformer role; the rewrite is an optional later step run by the human.* | 2026-10-27 |
| D2 | ~~Platforms: Linux and macOS. On Windows, a POSIX shell such as Git Bash.~~ Superseded by D17. | 2026-10-27 |
| D3 | One file per task, as in v1. | 2026-10-27 |
| D4 | The Reformer rewrites the project once, at the very end. | 2026-10-27 |
| D5 | **One global dependency graph, ready-based scheduling, no speculation.** The Planner maintains and extends one graph while the Runner runs. A task runs as soon as everything it uses is proved. Each node's statement is written by the Planner as a stub in its task file (normal theorem, `sorry` proof). The Runner never lets a task import an unproved node. The only number is a resource ceiling (made concrete in D18): parallelism = min(ready tasks, ceiling). The Planner's metric is the critical path; the Runner reports ready width and critical path live. Replaces v1's stages, conditional claims, `Work` wrappers, assemblers and completion files. *Amended by D53: stubs are a task's current statement; statements are not frozen.* | 2026-10-27 |
| D6 | **The Runner is a deterministic program** with no model. Monitoring and recovery decisions go to the Planner. *Amended by D38: infrastructure recovery goes to the human.* | 2026-10-27 |
| D7 | **Fixer flow: finish, split (one level), or escalate.** *Finish:* a complete proof goes straight to the checker. *Split:* the Fixer adds new nodes (stub statements) and saves a candidate proof of the original task that uses them; the Runner checks the original statement is unchanged, the new statements elaborate and there are no cycles; the saved candidate is re-checked automatically once the new nodes are proved. A partial proof is a split with one remaining node; there is no returning-Prover phase. A node created by a split that fails and would need splitting again goes to the Planner. *Escalate:* the statement looks false or must change; goes to the Planner, and to the human if it is a top-level statement. | 2026-10-27 |
| D8 | **Reformer scope:** rewrite proofs, reorganise files by topic, rename. Statement meanings and definitions stay fixed. A contract-check file maps each renamed or restated top theorem to its frozen statement. | 2026-10-27 |
| D9 | The v1 **Repairer is renamed the Fixer.** | 2026-10-27 |
| D10 | **The Planner does not write difficult tasks.** It sizes nodes so the Prover is expected to finish on the first attempt, and splits a difficult argument into more nodes rather than proving it itself. Fixer calls are the exception, not part of the normal flow. | 2026-10-27 |
| D11 | **Difficulty is judged by the Planner, with Runner feedback.** The Runner reports per node: attempts, time used, Fixer calls. The Planner adjusts how it sizes similar nodes. No numeric target. | 2026-10-27 |
| D12 | **No one-claim restriction.** A task is a logically coherent unit that the Prover is expected to pass on the first attempt within the time limit. Its file may hold several frozen theorem statements; each is checked. Refines D3: still one file per task. | 2026-10-27 |
| D13 | **A Fixer split needs no Planner approval; the Planner is notified.** The Runner applies four guards before adopting a split: (1) original statements unchanged, new statements elaborate, no cycles; (2) the saved candidate compiles against the new stubs and its own proof has no `sorry` (validation only; acceptance waits for the new nodes, per D5); (3) a new statement matching an existing proved theorem is replaced by it; (4) new nodes live next to the original node. A fix that needs another node's statement or a definition to change is an escalation, not a split. | 2026-10-27 |
| D14 | **A task may import any proved node.** Readiness still follows the dependencies the Planner declared; the receipt records the file's actual imports. | 2026-10-27 |
| D15 | **Helpers are public by default, inside the node's own namespace.** The checker requires every non-private declaration to start with the node's namespace, and forbids global side effects: instances, `@[simp]`, notation and attribute changes must be `local` or `scoped`. | 2026-10-27 |
| D16 | **Small packet, search on demand.** The packet holds the statements to prove, the Planner's short list of relevant lemmas (name and statement, no proof) and a one-line-per-module table of contents. Everything else on demand: project index search, `exact?`, Loogle, `read_file`. The Prover prompt says: try `exact?` before writing a helper. | 2026-10-27 |
| D17 | **The formalisation always runs on Linux, with one native container per attempt** (Docker or Podman). Every Prover attempt, Fixer attempt and check runs in its own short-lived container from one image (pinned Lean, Mathlib cache, Lean MCP server); only that attempt's workspace is writable; Mathlib is shared read-only. Supersedes D2. The Planner and the human may work from any machine that can reach the Linux host (D33). | 2026-10-27 |
| D18 | **Minimal resource ceiling.** A fixed number N of concurrent attempts; each attempt container has a memory cap with swap off; an attempt's acceptance checks run within its slot (one container at a time, D43); running out of memory is reported to the Prover like any tool error and never stops the campaign. | 2026-10-27 |
| D19 | **Independent `verify` and attribution.** `verify` works from a clean checkout of a commit, in the pinned image, offline, with no agents: it rebuilds and re-checks every top theorem's exact statement and axioms. Receipts are small files committed to the repository, recording the commit, toolchain, image digest, Runner version (D45), result, and who wrote each file (Prover, Fixer, Planner, Reformer). Integrity comes from Git; no separate hashing. | 2026-10-27 |
| D20 | **The human approves each top-level statement once**, from its target sheet. The approved version is a Git tag; the Runner refuses commits changing those statements without a new approval (Provers still fill in the proofs; review wording fix 2026-10-27). Internal nodes need no sign-off. | 2026-10-27 |
| D21 | **Deprecation warnings are ignored at acceptance**, as in v1. Deprecated names are fixed by the Reformer's upgrade (D22). | 2026-10-27 |
| D22 | **The Reformer moves the project to current Lean and Mathlib** (*only if the human chooses, D40*) as part of its rewrite, in steps through intermediate versions if the gap is large. Pins stay fixed during the campaign. `verify` and the contract-check file (D8, D19) check the upgraded result. *Amended by D53: Lean and Mathlib may also change at a pause during the campaign, with a full re-check.* | 2026-10-27 |
| D23 | **`maxHeartbeats` may be raised only per declaration** (`set_option maxHeartbeats N in` directly before one theorem). File-wide settings and `0` are rejected at acceptance; no numeric cap. At the end, a mechanical pass removes each raise and rebuilds, dropping every raise the build passes without. | 2026-10-27 |
| D24 | **Heartbeat guidance in the injected prompts, backed by feedback.** Planner: one main idea per expected proof; separate named theorems rather than long conjunctions; characterising lemmas for each new definition; one number system per statement where the mathematics allows; large numerical facts in their own nodes. Prover: split a declaration that runs out of heartbeats before raising; prefer `simp only` and `linarith only`; raise per declaration only when splitting is unreasonable. Runner: per-node feedback (D11) includes heartbeat raises; the end-of-campaign pass (D23) records which were necessary. | 2026-10-27 |
| D25 | **Models and budgets per campaign, from a suggested configuration confirmed in one step.** The Planner proposes the complete configuration in one message (model and reasoning setting for Planner, Prover, Fixer and Reformer, per D32; attempt time limit, concurrency N and memory cap from the setup measurement, any spending or wall-time cap); the human confirms or changes items. Nothing paid is chosen silently. | 2026-10-27 |
| D26 | **Live node submission.** The Planner submits nodes with a command; the Runner validates them (statements elaborate, no cycles, frozen nodes unchanged) and adds them immediately. A node's statement freezes when its first attempt starts; before that the Planner may revise or withdraw it. The Planner aims to keep at least N nodes ready. Resolves C2. *Amended by D53: statements no longer freeze; a change triggers re-checks instead.* | 2026-10-27 |
| D27 | **Event-driven monitoring.** The Runner does all monitoring itself and writes an event log plus an inbox of items needing a decision: escalations, ready nodes below N and completion for the Planner; infrastructure problems for the human (D38). The Planner works continuously (D28) and reads the inbox between tasks; Fixer splits and other routine events are recorded for its review. There is no timed observation schedule. The human gets a short Runner-generated summary at a cadence they set. | 2026-10-27 |
| D28 | **One long-lived Planner session** that keeps extending the graph and reads the inbox between tasks, relying on the agent tool's auto-compaction. Safeguards: (1) files on disk are the source of truth and the Planner re-reads them rather than trusting its memory; (2) the Planner's rules live in the instruction file its agent tool loads automatically (e.g. `CLAUDE.md`, `AGENTS.md`), so they survive compaction; (3) the Runner alerts the human if the inbox goes unread for longer than a set period; a restart is a new session with the standard prompt. Provers and Fixers never message anyone; one Planner session at a time. | 2026-10-27 |
| D29 | **A new Runner reusing two proven parts of v1:** the acceptance check (audit file for exact statement and allowed axioms) and the Prover tool loop (model calls, Lean MCP tool serving, source-editing tools). Everything else is written new, with v1's tests as a reference. | 2026-10-27 |
| D30 | **Planner and Fixer run on any agent CLI with a non-interactive mode**, through a small adapter (command line plus flags), tested with two tools (for example Claude Code and Codex). The Prover is driven by the Runner through a model API. | 2026-10-27 |
| D31 | **No shipped example project; unit tests only.** Unit tests may still use tiny Lean fixture files. | 2026-10-27 |
| D32 | **Review defaults confirmed.** (1) D25's one-step configuration covers all four model roles: Planner, Prover, Fixer, Reformer. (2) A node goes to the Planner if its Fixer proof fails the checker, or if the Fixer attempt ends with neither a proof nor a split. (3) Fixer attempts count towards the N concurrent attempts of D18. (4) Target sheets for top-level statements (D20) use v1's `TARGET.md` template. (5) Command-line tool: `setup-check`, `run`, `status`, `submit`/`revise`/`withdraw`/`resolve` (Planner), `approve` (human), `verify`. | 2026-10-27 |
| D33 | **The Planner may run on any machine that can reach the Linux host.** Confirms D17's assumption. | 2026-10-27 |
| D34 | **The Fixer is called after exactly one failed Prover attempt per node**, as in v1. | 2026-10-27 |
| D35 | **The Reformer works as a plan, then checked tasks.** A Reformer agent writes a reorganisation plan (topic layout, names, which helpers to merge); the rewrite then runs as file-level tasks through the Runner, each checked against the frozen statements. | 2026-10-27 |
| D36 | **Infrastructure errors.** (1) The Runner handles routine cases itself: temporary provider errors retried with backoff inside the attempt; a crashed Lean server restarted and the Prover told; a failed container start retried once. (2) Otherwise it classifies the scope: attempt-local pauses only that node; host-wide or provider-wide stops new attempts while unaffected running attempts continue. (3) It preserves workspace, transcript, logs and time used; the node is *interrupted*, not failed, and keeps its Prover attempt. (4) It writes an inbox item (what failed, scope, evidence, what it tried). (5) The Planner resumes the same attempt with the remaining time, restarts it (only if the model never ran), holds the node, or asks the human, then resolves the item. (6) Repeated failures of the same kind go to the human. *Steps 4–5 amended by D38: infrastructure items go to the human, who continues the campaign with one command.* | 2026-10-27 |
| D37 | **Standing assumption: the Planner has full access to the Linux host** running the campaign. It uses that access for the initial setup, for Lean probes and Runner commands, and for anything the human asks of it (D47). It never changes the Runner (D45). | 2026-10-27 |
| D38 | **Infrastructure goes to the human.** Any infrastructure problem the Runner's own handling (D36 step 1) cannot solve goes to the human, not automatically to the Planner. The human fixes it, alone or with any assistant including the Planner (D47), and runs one Runner command to continue; the Runner then applies D36's resume rules mechanically (the command is `resume`, D52): each interrupted attempt resumes with its remaining time, and an attempt is restarted only if its model never ran. Amends D6, D27 and D36. *The earlier sentence restricting the Planner to mathematics after setup was removed by D47.* | 2026-10-27 |
| D39 | **The approval tag stays on the host.** The risk described in C12 is accepted. | 2026-10-27 |
| D40 | **Upgrading is the human's choice.** Before any upgrade, the Reformer asks the human whether the pinned version should be updated. If yes: the pinned, verified version stays the certified result; the Reformer ports the top statements first, changing only what the upgrade forces; the human re-approves the ported statements (D20); the upgraded library's `verify` and contract-check file refer to those; if the upgrade cannot be completed, the pinned version remains the result. Amends D22. | 2026-10-27 |
| D41 | **Definitions belong to the Planner.** The Planner writes definitions, and any instances they need, in its own definition files; each is checked to elaborate and freezes once an attempt starts on a node that uses it. Task files hold theorems and helper lemmas only (which is what lets D15 forbid global instances there). Characterising lemmas beyond trivial `rfl` facts are ordinary nodes for Provers (C5). *Amended by D53: definitions no longer freeze; a change triggers re-checks.* | 2026-10-27 |
| D42 | **The unit tests (D31) include scripted end-to-end flow tests** with recorded model responses for the risky hand-offs: split adoption, re-check after a split, resume after an interruption, live submission. | 2026-10-27 |
| D43 | **Second-review defaults.** (1) The human is a participant: approves top statements (D20), confirms the configuration (D25), handles infrastructure (D38), decides escalated top-level statements (D7), and decides whether to upgrade (D40). (2) A Fixer writing new statements in a split follows the Planner's statement rules (D10, D24), which go into its prompt. (3) When the Prover asks for its acceptance check, its attempt container, Lean server included, is stopped completely and the check runs in its own container. If the check passes, the attempt is over. If it fails, a fresh container on the same workspace resumes the attempt with the check's diagnostics and the remaining time; the conversation is held by the Runner, so nothing is lost but the Lean server's loaded state. The time limit keeps counting during the check. A slot therefore holds one container at a time. (4) End-of-campaign order: Reformer plan; rewrite and, if chosen, upgrade; heartbeat pass (D23) on the final version; `verify`. | 2026-10-27 |
| D44 | **What the Fixer inherits:** a copy of the Prover's whole workspace folder (scratch files and saved helpers included); the node's packet, the last check's diagnostics and the Prover's final message stating the obstacle; the Prover's transcript on disk, readable on demand but not pasted in; a fresh conversation and the Fixer's own time limit. | 2026-10-27 |
| D45 | **The Runner never changes during a campaign**, not even through the Planner acting as the human's assistant. A Runner bug that blocks the campaign stops it; any fix is a protocol revision made afterwards, and continuing the work is a new campaign on the same project. Receipts record the Runner version that accepted each node (extends D19). | 2026-10-27 |
| D46 | **A lessons file is kept.** The protocol ships a cumulative lessons file from earlier campaigns, which the Planner reads and uses. During a campaign the Planner (and the human) add entries to the campaign's copy, committed in the project repository: the lesson, its evidence (nodes, receipts, logs), and any suggested protocol change. The Planner may apply a lesson at once only through its own planning (sizing, statements, packets); changes to the Runner, prompts or checks wait for the revision after the campaign, where the human and a revision agent merge the entries and turn them into checks where possible. *Amended by D50 and D53: prompts and the Planner's rules may now be changed during the campaign by the human (the Planner may propose changes); only changes to the Runner's code wait for the revision.* | 2026-10-27 |
| D47 | **The Planner's role is not restricted to mathematics after setup.** The human may use the Planner as an assistant throughout the campaign, including for infrastructure problems. Removes the corresponding sentence from D38 and the note in D37. | 2026-10-27 |
| D48 | **Terminology and the reference file.** `DESIGN.md` is written for the human, without decision numbers. Terms: *task*, not node; all tasks live in the dependency graph of all tasks; a task *can be attempted* when its dependencies are proved (not "ready", which can be read as "proved"); *depth* of the dependency graph, not critical path; no "contract-check file" term (the Reformer proves that each renamed or restated top theorem gives the approved statement, and the Runner checks it). This log keeps the older terms where they were used at the time. | 2026-10-27 |
| D49 | **The Planner may write very simple proofs about its definitions.** Besides `rfl` lemmas, the Planner may prove helpful, very simple facts about definitions that it anticipates will be needed often but that are too small for a task (for example `fieldKind_eq_one_or_two`), while it checks the definition. They are recorded as written by the Planner. Anything needing real thought stays a Prover task. This must be stated in the Planner's prompt. Refines D41. | 2026-10-27 |
| D50 | **The Prover and Fixer prompts may change during a campaign.** Attempts started after a change use the new version; receipts record which prompt version each attempt used. Answers Q39 (the assumption that prompts stay fixed is withdrawn). | 2026-10-27 |
| D51 | **Freeze as little as possible.** When the human decides to change something mid-campaign, the protocol must not break down. Only the Runner's code stays fixed for a campaign (D45); for everything else the Runner works out the consequences of a change. Concrete rules: Q41, Q42. | 2026-10-27 |
| D52 | **Pause, interruptions and recovery: one mechanism.** `pause` (no new attempts; running ones finish; changes can be made); `pause --now` (running attempts also stopped and marked interrupted); `resume` (the continue command of D38: picks up all changes; interrupted attempts continue with their remaining time in the same workspace and conversation, restarted from scratch only if the model never ran). A Runner crash or host reboot is an unplanned `pause --now`: on restart the Runner rebuilds its state from disk, removes leftover containers and marks running attempts interrupted, and the human runs `resume` (no automatic resume, so no restart loops). Time used is written to disk every few seconds. An interrupted Fixer resumes through its tool's session-resume feature if the adapter supports it, otherwise restarts on the same workspace with its remaining time and the interrupted transcript. No interruption uses up a Prover or Fixer attempt. | 2026-10-27 |
| D53 | **What may change mid-campaign.** Only the Runner's code is fixed. Configuration, prompts, the Planner's rules and the container image's tools apply to attempts started afterwards; receipts record the versions. A task's statement or a definition may change at any time (top-level statements also need new approval, D20): attempts running on affected tasks are cancelled without counting as failures; the changed task and everything depending on it lose their proved status; the Runner re-checks the existing proofs against the new statements automatically; only failing ones become tasks that can be attempted, starting from their previous proof and the new diagnostics. Removing a task others use is refused until they are changed. Lean or Mathlib versions may change at a pause, at the cost of a full rebuild and the same re-check. Replaces the freezes in D5, D26 and D41, and "versions fixed for the campaign" in D22 and D40. | 2026-10-27 |
| D54 | **Attempt containers have no network.** The Runner carries out the Prover's Loogle and LeanSearch calls itself, outside the container. Token cost is unchanged. | 2026-10-27 |
| D55 | **The Fixer runs on the host, spawned by the Runner.** Its agent tool is logged in on the host, so no credentials ever enter a container; the host (and the Runner) has internet access. The Fixer's tool is restricted to its own workspace by the tool's own sandbox, and its Lean work (builds, Lean server) runs in its attempt container. Amends D17. | 2026-10-27 |
| D56 | **The Reformer is merged into the Planner.** Once all tasks are proved, the Planner takes on the end-of-campaign work: it writes the reorganisation plan, asks the human about upgrading, and submits rewrite tasks. *Proposed, to confirm:* rewrite tasks are carried out by Provers with a rewrite prompt and checked by the Runner like any task, with the Fixer if needed. Participants are now Planner, Runner, Prover and Fixer, plus the human. Amends D1, D4, D8, D19, D25, D30, D32, D35, D40 and D43. *Superseded by D57: the rewrite is no longer a campaign step at all.* | 2026-10-27 |
| D57 | **No Reformer; the rewrite is an optional later step run by the human.** After the campaign, the human may rewrite the project for quality (and optionally upgrade Lean and Mathlib), tasking the Planner or starting a new agent from their own machine. Its job and what it must take into account are described in `REFORM.md`. The campaign itself ends when every top-level statement is proved, with the Runner's heartbeat pass and `verify`; the verified commit is the certified result. Supersedes the Reformer parts of D1, D4, D8, D22, D35, D40, D43 and D56. | 2026-10-27 |
| D58 | **The Planner is trusted and never has to go through the Runner.** It may run its own Lean checks directly and start worker agents, for example to calibrate task difficulty. Acceptance is unchanged: only the Runner's check makes a proof count, whoever wrote it. Refines D11 (calibration may also use trial runs) and D18 (the Planner's own work runs outside the attempt ceiling). | 2026-10-27 |
| D59 | **If the optional rewrite runs through the Runner, Provers carry out the rewrite tasks**, with a rewrite prompt, checked like any task. The protocol therefore ships a Prover rewrite prompt. | 2026-10-27 |
| D60 | **The Runner is written in Python**, like Baker's runner (whose acceptance check and Prover loop are reused). | 2026-10-27 |
| D61 | **The Prover loop supports both chat completions and Anthropic's own API**, through a small translation layer, so Claude models can be Provers and prompt caching can cut the cost of resending the conversation. The loop stays append-only (never edits earlier turns), as Baker's already is. | 2026-10-27 |

## Consequences to resolve

- ~~**C1 (from D2).** The v1 engine is Linux-only.~~ Resolved by D17: execution is Linux-only. Stopping an attempt means stopping its container, so v1's `/proc`/`prctl` process tracking is no longer needed.
- ~~**C2 (from D5).**~~ Resolved by D26. The Runner must accept graph additions while running. v1 required a stopped boundary to deploy. Additions must be append-only and validated (statements elaborate, frozen nodes unchanged, no cycles).
- **C3 (from D5).** The acceptance check replaces v1's "undeclared task dependency" rule with "imports only proved nodes", and stores each task's current statement for comparison (D53).
- **C4 (from D6, D38).** The Runner must stop cleanly on infrastructure errors and leave a report the human can act on, plus a single command to continue afterwards.
- **C5 (from D10).** Two tensions to keep in view:
  - *With v1's authorship lesson.* Stage 4's continuation made tasks easy by having the preparer prove the hard arguments, leaving trivial leaves. D10 must be met by splitting into nodes, not by the Planner doing the central proofs.
  - *With overhead and the critical path.* Each extra node costs a packet, a compile and a check; splitting a long argument into a chain also lengthens the critical path.

- **C6 (from D12).** Lean imports whole files, so a dependent waits until *every* theorem in the node it imports is proved. The Planner should group theorems that are needed together, and keep apart theorems that other nodes need early.

- **C7 (from D16).** The Runner must build and update a project index after each acceptance (one line per public declaration: name, statement, module, first docstring line) and provide a search tool over it that returns matching lines only.
- **C8 (from D15).** The namespace-prefix and no-global-side-effect rules are added to the acceptance audit.
- **C9 (from D28, D30).** Agent tools load their instruction file (`CLAUDE.md`, `AGENTS.md`) from the working directory and its parents. The Planner's rules file must therefore live outside the project tree, or be excluded from attempt snapshots; otherwise a Fixer started in a snapshot would load the Planner's rules. The Fixer gets its own rules file in its workspace. The Prover reads no such file: the Runner sends its rules as the system message with every request.
- ~~**C11 (from D33).**~~ Largely resolved by D37: the Planner has full access to the host, so it can run Lean probes and Runner commands directly. It still needs a repository clone if it works from another machine.
- **C12 (from D37).** A Planner with full host access can bypass the Runner's checks: edit the canonical repository directly, change the Runner, or move the approval tag of D20. Mistakes are more likely than intent, but D20's guarantee depends on the approved statements being out of the Planner's reach. Accepted by D39: the tag stays on the host.
- **C13 (from D17, D43).** One Lean server per attempt, inside the attempt's container, never shared, as in v1 (`runner.py:905–911`; Stage 91 started 8 servers for 8 tasks). A shared server would need to see every workspace, which breaks the isolation of D17, and one crash or memory blow-up would hit every attempt. Memory cost is modest: Mathlib's compiled files are memory-mapped, so the servers share those pages; each holds only its own elaboration state.
- **C14 (from D17).** Attempts see the compiled files of proved nodes read-only, from one controller-owned build cache that grows as nodes are accepted, plus a private writable layer for their own outputs. v1 instead copied the whole build directory into every attempt (`runner.py:353`), which is how Stage 8 ran out of disk.
- **C15 (from D58).** The Planner's own Lean checks and worker agents use the host outside the Runner's ceiling, so N and the memory cap must leave headroom for them, and their model costs count against any spending cap agreed in the configuration (D25). Worker results are not accepted proofs.
- **C10 (from D31).** With no example project, the setup check on a new host needs its own small command: build one tiny Lean file in the container image, run the acceptance check on a known-good and a known-bad file, confirm the memory cap applies, make one model request per configured role, and run `verify` on the result.

## Open questions

### Current batch
- **Q48 How the Fixer runs** (reworded 2026-10-27 after the user asked which Fixer tools justify an adapter). The Fixer needs no tool the Runner's own loop could not provide: reading and editing files, Lean checks, Lean server queries, lemma search, plus two new ones (propose a split, escalate). Options:
  - a) *The Fixer runs in the Runner's own loop, like the Prover*, with its own model, prompt and time limit and the two extra tools. No adapters at all; the Fixer runs fully inside its container; it is billed through the model API. Supersedes the host-side arrangement of D55.
  - b) *The Fixer is an agent tool (Claude Code or Codex) started through adapters.* Lets the Fixer use a subscription login instead of per-token API billing (Baker's Repairer ran on a ChatGPT login), and those tools' own harness. Costs: one adapter per tool, and the host-side sandbox setup of D55.

  Either way there is no Planner adapter: the human starts the Planner, which needs only its instruction file (`CLAUDE.md` or `AGENTS.md`) and a start prompt.

## What the role prompts must say

Collected from the decisions, so nothing is lost when the prompts are written.

- **Planner:**
  - propose the full configuration in one message (D25, D32);
  - write a target sheet for each top-level statement (D20);
  - write the definitions (D41); besides `rfl` lemmas, it may write helpful, very simple proofs about definitions that it anticipates will be needed often but that are too small for a task (D49);
  - no difficult tasks: split rather than prove the central arguments itself (D10, C5); learn from the Runner's per-task reports (D11);
  - statement rules: one main idea per expected proof, separate named theorems rather than long conjunctions, one number system per statement where possible, large numerical facts in their own tasks (D24);
  - group in one file only theorems that are needed together (C6); keep the depth of the dependency graph small; keep at least N tasks that can be attempted (D26);
  - files on disk are the truth: re-read them rather than relying on memory (D28);
  - read and add to the lessons file; apply lessons only through its own planning (D46);
  - never change the Runner (D45).
- **Prover:**
  - search on demand; try `exact?` before writing a helper (D16);
  - helpers public in the task's namespace; no global changes (D15);
  - if a declaration runs out of heartbeats, split it first; prefer `simp only` and `linarith only`; raise heartbeats only for a single declaration (D23, D24);
  - save useful partial work in the task file; once the check passes, stop; if blocked, end with a message stating the obstacle precisely (v1 practice, relied on by D44).
- **Fixer:**
  - start from the inherited workspace, diagnostics, the Prover's final message and, if useful, its transcript (D44);
  - finish, split one level, or escalate; never change another task's statement or a definition (D7, D13);
  - new statements follow the Planner's statement rules (D43).
- **Planner, additionally:** may run its own Lean checks and start worker agents to calibrate difficulty; their results are not accepted proofs (D58).
- **Prover, on a rewrite task** (optional rewrite run through the Runner, D59): rewrite the file following the plan, keeping every statement's meaning; prove that each renamed or restated top-level theorem gives the approved statement.
- **The optional rewrite after the campaign** has its own brief, `REFORM.md` (D57).

## Closed questions

- **Q1 Runner.** Decided as D6 (program only). Rejected: program plus an operator agent.
- **Q2 Completion files.** Closed by D5: no conditional assemblers or completion files. The top theorem is an ordinary node whose dependencies are the lemmas it uses.
- **Q3 Repair flow.** Decided as D7 (split depth one). Rejected: split depth two; no splitting; v1's return to the Prover.
- **Q4 Reformer scope.** Decided as D8. Rejected: proofs and layout only; everything including definitions.
- **Q47 Prover model API.** Decided as D61 (both).
- **Q46 Who carries out the rewrite tasks.** Decided as D59: Provers with a rewrite prompt, if the optional rewrite runs through the Runner.
- **Q45 The Planner's Lean probes.** Decided as D58: the Planner is trusted and works directly, outside the Runner. Rejected: probes through the Runner, counted against the ceiling.
- **Q43 Network inside attempt containers.** Decided as D54 (offline; the Runner carries out the search calls).
- **Q44 Where the Fixer runs and how it reaches its model.** Decided as D55 (on the host, logged in there; tool sandbox limited to its workspace; Lean in its container). The Reformer part of the question lapsed with D56.
- **Q41 Pause, interruptions and recovery.** Decided as D52.
- **Q42 What may change mid-campaign.** Decided as D53.
- **Q39 Prompts during a campaign.** Decided as D50: the Prover and Fixer prompts may change.
- **Q40 Basic lemmas the Planner may prove itself.** Decided as D49 (option a, with the user's wording for the Planner prompt). Rejected: `rfl` lemmas only.
- **Q38 Changing the Runner during a campaign.** Decided as D45 (never during a campaign) and D46 (lessons file for the revision afterwards). Rejected: fixes during the campaign by the human; patches by the Planner.
- **Q37 What the Fixer inherits.** Decided as D44. Rejected: v1's set; pasting the full Prover transcript.
- **Q33 Upgrade versus frozen statements.** Decided as D40: the Reformer asks the human first; if yes, port statements, re-approve, verify; the pinned version stays certified.
- **Q34 Definitions.** Decided as D41 (the Planner's).
- **Q35 Scripted flow tests.** Decided as D42.
- **Q36 Small gaps.** Decided as D43; item 3 changed at the user's suggestion from "pause the Lean server" to "stop the attempt container completely during the check".
- **Q31 Human notification.** Decided as D38: infrastructure the Runner cannot solve goes to the human; the Planner works only on the mathematics after setup (*this second part was removed by D47*). Rejected: host-wide problems to the Planner; immediate human notification for every host-wide problem.
- **Q32 Where the approval tag lives.** Decided as D39 (on the host). Rejected: a remote with protected tags or the human's clone.
- **Q29 Infrastructure errors.** Decided as D36. Rejected: stop the whole Runner; automatic retries only.
- **Q27 Where the Planner runs.** Decided as D33 (any machine that can reach the host). Rejected: on the Linux host only.
- **Q28 When the Fixer is called.** Decided as D34 (after one failed Prover attempt). Rejected: a second Prover attempt first.
- **Q30 How the Reformer works.** Decided as D35 (plan, then checked tasks). Rejected: one session rewrites everything.
- **Q26 Review defaults.** Confirmed as D32.
- **Q25 Example project.** Decided as D31 (unit tests only). Rejected: small example with replay mode; larger live example.
- **Q23 Runner implementation.** Decided as D29. Rejected: modify v1 step by step; rewrite reusing nothing.
- **Q24 Agent tools for Planner and Fixer.** Decided as D30. Rejected: one specific tool; untested "any".
- **Q22 How the Planner runs.** Decided as D28 (one long-lived session, with safeguards). Rejected: bounded sessions restarted by a loop; wake on events only.
- **Q19 Models and time budgets.** Decided as D25. Rejected: fixed protocol defaults; every setting negotiated individually.
- **Q20 Adding nodes while running.** Decided as D26 (live submission). Rejected: additions only while stopped; whole graph up front.
- **Q21 Monitoring.** Decided as D27 (event-driven). Rejected: fixed polling; human monitors.
- **Q18 Heartbeat guidance.** Decided as D24 (Planner rules, Prover rules, feedback). Rejected: Prover rules only; none.
- **Q17 Raising `maxHeartbeats`.** Decided as D23 (per declaration only). Rejected: forbidden; allowed freely.
- **Q15 Deprecated names at acceptance.** Decided as D21 (ignore). Rejected: reject submissions using deprecated names.
- **Q16 Upgrading pins at the end.** Decided as D22 (Reformer upgrades). Rejected: keep campaign pins; separate later project.
- **Q12 Resource ceiling.** Decided as D18 (minimal version). Rejected: five-point plan; N only without memory caps.
- **Q13 Receipts and verification.** Decided as D19. Rejected: Runner receipts only.
- **Q14 Sign-off of top-level statements.** Decided as D20. Rejected: delegated to the Planner; approval of every node.
- **Q11 Isolation.** Decided as D17 (Linux, native containers per attempt). Rejected: containers on all platforms inside a VM; native sandbox per OS; no OS sandbox.
- **Q8 Imports.** Decided as D14. Rejected: declared dependencies only.
- **Q9 Helper visibility.** Decided as D15. Rejected: private by default; public only when the Planner declares exports.
- **Q10 Packet contents.** Decided as D16. Rejected: v1-style full file text; statements only.
- **Q7 Planner involvement in a Fixer split.** Decided as D13 (notify only). Rejected: Planner approves every split; Planner approves only large splits.
- **Q6 Judging difficulty.** Decided as D11 (judgement plus Runner feedback). Rejected: a written size guide; a probe attempt before freezing.
- **Claims per task** (later-batch item). Decided as D12: several theorems per task allowed.
- **Q5 Parallelisation mechanism.** Decided as D5 (option d). Rejected: a) stubs used as dependencies; b) conditional claims for same-stage siblings only; c) conditional claims as in v1.

## Evidence

### First-attempt rate in Baker (relevant to D10)

The final campaign (Stages 16–91) added 495 tasks: 476 accepted on the first attempt (96%), 19 after one repair (`provenance/three-log-campaign/FINAL_REPORT.txt`). Stage 3 was the opposite case: 52 tasks, 69 proof attempts, 10 architecture workflows.

### Architecture repairs in Baker (checked 2026-10-27)

The v1 Repairer returned one of four dispositions (`engine/runner.py:1005–1020`): `proof`/`partial` (returned to the Prover for a final attempt), `architecture` (task blocked until the Planner adopted it), `infrastructure` (controller stopped).

- **Stage 3 (22–24 Oct, older batch runner):** 10 architecture workflows across 9 goals, plus 3 on FG02 (`reference/campaign/baker-stage3-audit/AUDIT.txt`).
  - `I_rank_minor`: the Repairer moved minor extraction and normalization into its own proof and exposed a new task `I_rank_rows`, which Flash proved in about 11.6 min. Code: `Architecture/BatchThree/P01_rank.lean`. New `RectangleRowsClaim` at line 16; `theorem I_rank_minor (h : RectangleRowsClaim)` at line 254.
  - `HX02`: two split rounds (sorted placement, then `HX02_padded_sum`); the Repairer proved the witness/order part, Flash the remaining sum. Under D7 the second round would go to the Planner.
  - FG02: false protected statement (implication/equivalence grouping). Architect calls could not fix it. Resolved by an authorized spec correction, then all Batch 3 sources were recompiled against it.
  - Adoption of the Repairer's new-task records crashed three runners (`runner._adopt`, TypeError on unhashable dict). The audit recommended a checked hand-off format, and routing refuted statements straight to a spec decision.
- **Stages 4–91 (canonical Git history, 77 commits to `tasks.json`):** no task removed, no claim changed, no frozen spec or assembly file edited. Later repairs were proof repairs.

Implications: splitting works mathematically but needs a validated hand-off format and a regression test. Distinguish a statement-preserving split (automatic) from a statement that is false or must change (Planner, or the human, immediately).

### Conditional claims in Baker (measured 2026-10-27)

- 500 of 727 tasks had conditional claims: 1,412 premises, median 2 per claim, max 11.
- Only 617 premises (44%) were same-stage sibling claims (needed for parallelism). 795 (56%) were results already proved in earlier stages, present only because tasks could not import earlier proof files.
- Machinery: 691 `…Work` wrappers, 90 assemblers (median 15 lines), 95 completion files.
- v1 deleted `sorry` skeletons on purpose (its design note D03: no accepted work resting on "fake predecessor theorems"). D5 keeps that guarantee: stubs are statements only, never imported before they are proved.

### Ready-based scheduling on the Baker graph (measured 2026-10-27)

If every Baker task had waited for its real dependencies (premises and imports; 6,934 edges, over-approximated for whole-stage results):
- Critical path: 95 tasks. Ready tasks per level: max 110 (at the start), median 5.
- Critical-path proving time: about 6.3 h at 4 min per task (Stage 91 median), about 24 h at 15 min (the 900 s limit). The real campaign took about 25 h for Stages 16–91, mostly preparation.
- The graph was built from claims designed for v1 staging; a Planner aiming at short chains would do better.

### Containers and memory (2026-10-27)

- **Linux:** a container is ordinary processes with namespace and cgroup fences; no VM. Extra memory per container is a few MB (the runtime shim). Lean maps `.olean` files into memory instead of copying them, so containers reading Mathlib from the same read-only image layer or volume share those pages. Copying the cache into each container would lose that.
- **macOS and Windows:** containers run inside a Linux VM (Docker Desktop, OrbStack, colima; WSL2 on Windows). Costs: the VM's memory allowance is unavailable to the host while in use, and some tools return unused memory slowly; a few hundred MB VM baseline; host-folder mounts are slow for Lean's many small files, so the project and caches should live inside the VM.
- **Lean dominates either way.** Baker never recorded peak RAM per attempt. The Stage 3 audit: on the 64 GB server, 15 concurrent projects reached about 16 GiB swap; five projects about 3.2 GiB swap; no OOM kills; summed RSS double-counts shared Mathlib mappings. The final setup ran six Provers and one Repairer. Measure at setup: containers give per-attempt memory accounting.

### Integrity via Git (2026-10-27, basis of D19 and D20)

No protocol-specific hashing. A commit ID pins every file in the project, including `lean-toolchain` and `lake-manifest.json` (which pins Mathlib by commit). v1 receipts already recorded Git object IDs (`engine/runner.py:105`). Receipts are small files committed to the repository, so one commit covers sources and receipts; v1 kept them in the ignored `.runner/` folder. Approved top statements are a Git tag, and the Runner refuses any commit that changes those files without a new approval (`git diff <tag>`). The container image is identified by the digest Docker already provides, recorded in a committed file. Transfer uses the Git repository or a bundle (`git bundle verify`). Baker's export added a 2.9 MB `MANIFEST.json` and a 49 MB `SOURCE_PATHS.jsonl.gz` of SHA-256 records next to a 4.3 MB bundle holding all 74 branches; the bundle alone would have covered the canonical sources.

### Pinning and upgrade debt (measured 2026-10-27)

- Baker pins Lean `v4.34.1` (`lean-toolchain`) and nine packages by commit (`lake-manifest.json`): Mathlib `d13f23b`, batteries, aesop, Qq, ProofWidgets, plausible, importGraph, LeanSearchClient, Cli.
- Pinning is correct: the same commit builds the same everywhere, which is what makes receipts meaningful. The cost is upgrade debt: Mathlib renames and deprecates names (keeping aliases only for a while), changes simp sets and tactic behaviour, and Lean itself changes with each release.
- The pinned Mathlib already marks 4,252 declarations as deprecated. 24 of 727 Baker task files use 9 of them by full name, deprecated between 2026-04-08 and 2026-07-17. Examples, verified in source: `MvPolynomial.coeff_add` (since 2026-07-06, 12 files), `Set.mem_setOf_eq` (since 2026-07-09, 4 files), `ENat.coe_le_coe` (since 2026-07-17, 3 files). Lower bound: uses through `open` are not counted. The Provers wrote these despite the warnings, because v1 told them to ignore deprecation warnings.
- Other upgrade risks in Baker: 143 fragile simp-then-rigid sequences; 77 files raising `maxHeartbeats`, whose proofs sit near time limits that change between versions.

### Heartbeat raises in Baker (measured 2026-10-27)

- 77 of 727 task files raise `maxHeartbeats`. 71 of the 78 settings are file-wide; only 7 apply to a single declaration. Values: 1,000,000 (five times the default of 200,000) in 52 files, then 2,000,000 (13), 1,600,000 (6), 800,000 (3), 4,000,000 (2), 1,200,000 and 400,000 (one each).
- Copying: 44% of raising files had a context file containing a `maxHeartbeats` setting, against 2% of the other files. The background files hold at least 31 copies of `set_option maxHeartbeats 1000000`, all inside pasted proof code; the Planner never gave heartbeat advice.
- Some raises were plausibly needed: raising files have longer proofs (median longest declaration 94 lines against 54) and slightly more heavy automation (37 against 29 uses per 1,000 lines).
- Raising files show the bundled-claim and cast patterns far more often (correlation, not proof of cause): one `obtain` unpacking 10+ components in 21% of them against 4% of the others; positional `.2.2.1`-style access in 40% against 16%; cast tactics (`exact_mod_cast`, `push_cast`, `norm_cast`) at a median 7 per 1,000 lines against 0.
- Whether each raise was necessary can only be settled by rebuilding at the default, which was not possible here (no compiled Mathlib).

## Glossary

- **Node:** one task in the dependency graph: one file, one frozen statement (stub), one proof.
- **Ready:** a node whose imports are all proved.
- **Resource ceiling:** the maximum number of simultaneous Provers and Lean processes; the only fixed number in scheduling.
- **Critical path:** the longest chain of dependent nodes; the lower bound on proving time.
- **Fixer:** v2 name for v1's Repairer (D9).
- *v1 terms, not used in v2:* **conditional assembler** (a theorem whose hypotheses are a stage's task claims and whose conclusion is the stage's result); **completion file** (applies the assembler to the accepted proofs).
