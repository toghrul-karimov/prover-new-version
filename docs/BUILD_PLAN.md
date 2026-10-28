# Lean formalisation protocol v2: build plan

Drafted 2026-10-27. The design is in `DESIGN.md`; decisions and open questions are in `DECISIONS.md`.

## Work items

1. **Specification of the interfaces between the parts.** Everything else is built against it.
   - Task graph file: task, file, statements, dependencies, the packet's lemma list.
   - Formats: receipts, inbox and events, configuration, lessons file, target sheet.
   - Command-line interface.
   - The Prover's tool list.
   - What the Fixer receives and returns, including the exact split hand-off format.
   - Sandbox contract: what each sandbox sees.
2. **`verify`**: a small separate program, independent of the Runner and short enough to read; a thin wrapper around `lake comparator` (Lean v4.35.0 or later).
3. **Acceptance checker**: Baker's audit plus the new rules, with a positive and a negative test per rule.
4. **Campaign setup** (no image): pinned Lean through elan, Mathlib fetched once, the Lean server tools, Loogle, the list of Mathlib names, and Claude Code and Codex at fixed versions for agent-tool roles. Redone when the pins change.
5. **Runner:**
   - scheduling over the dependency graph, and the live depth;
   - sandboxes (bubblewrap) and memory caps (systemd scopes);
   - the model-API loop for Provers and Fixers (reused from Baker), supporting chat completions and Anthropic's API;
   - Fixer runs and split adoption with its four guards;
   - receipts in Git, and the lemma index with its search tool;
   - the shared Loogle process and the LeanSearch calls with their name filter;
   - inbox, events and notifications;
   - pause, resume and crash recovery;
   - the automatic re-check after changes;
   - `status` and `setup-check`;
   - the end-of-campaign heartbeat pass.
6. **Adapters** for Claude Code and Codex, used by Provers and Fixers that run as agent tools inside their sandboxes: command line and model, the campaign's own login folder (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`) and `runner login`, session resume, installing the prompt as the tool's instruction file, usage-limit detection and reset time, reading the result. The Planner needs no adapter.
7. **Prompts and templates**, from the checklist in `DESIGN.md` section 16.
   - Prompts: the Planner's instruction file and start prompt; the Prover prompt, plus a Prover rewrite prompt for the optional rewrite after a campaign (brief in `REFORM.md`); the Fixer prompt.
   - Templates: target sheet, configuration proposal, lessons-file entry.
8. **Initial lessons file**: Baker's lessons condensed for v2, each marked either "now an automatic check" or "still guidance".
9. **Tests**: unit tests, a fake model server, tiny Lean files, and scripted end-to-end runs of splits, resume after a crash, and changes mid-campaign.
10. **User guide**: setup, `setup-check`, configuration, approvals, pause and resume, end of campaign.
11. **Pilot campaign** on a small real theorem: the only end-to-end test with real models. Nothing is shipped from it. It also measures how long `lake comparator` takes per task (D94).

## Status (2026-10-28)

- **Item 1, specification:** draft 0.2; one open question, Q56.
- **Item 2, `lean-verify`:** written (`verify/lean_verify.py`); its Git checks have unit tests, and its Lean part has run on the test host (`docs/TEST_RESULTS.md`).
- **Test kit:** `scripts/setup-host.sh`, `tests/sandbox/probe.sh`, `tests/make-campaign.sh`, `tests/toy/` (17 variants), `tests/toy-mathlib/`.
- Everything else: not started.

## Order

1. Specification.
2. In parallel: `verify` and the checker; campaign setup; prompts and templates; the lessons file.
3. The Runner core with its scripted tests.
4. Adapters, `setup-check` and the user guide.
5. Pilot campaign.

## Open design questions (see `DECISIONS.md`)

Q56: comparing statements.

Settled since the first draft: sandboxes have no network, except agent sandboxes, which have the host's network (D99), and the Runner carries out the search calls; agent tools run inside their sandboxes (bubblewrap, no containers), logged in through the campaign's own login folder; there is no Reformer role: the rewrite is an optional later step run by the human (`REFORM.md`), with Provers doing rewrite tasks if it runs through the Runner; the Planner is trusted and runs its own Lean checks and worker agents directly.
