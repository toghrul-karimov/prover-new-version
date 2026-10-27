# Working on this repository (for AI agents)

This repository holds version 2 of a protocol in which AI agents formalise mathematics in Lean: a Planner writes tasks, a deterministic Runner schedules and checks them, Provers prove them, and a Fixer repairs failed tasks. The human, the repository's owner, makes the design decisions.

## State on 2026-10-27

- **Design: complete.**
  - `docs/DESIGN.md`: the plain overview, written for the human.
  - `docs/SPEC.md`: draft 0.2; files, formats, commands and checks.
  - `docs/DECISIONS.md`: decisions D1–D98 with their reasons, the evidence from the Baker campaign, and the glossary.
  - `docs/BUILD_PLAN.md`: the work items, in order.
  - `docs/REFORM.md`: the brief for the optional rewrite after a campaign.
- **Code:** only `verify/lean_verify.py`, the independent `lean-verify` (SPEC section 12.3), with unit tests for its Git checks. Its Lean part has never run, because no Lean was available where it was written. That part is the assumptions report and the call to `lake comparator`.
- **Test kit:**
  - `scripts/setup-host.sh` prepares the host;
  - `tests/sandbox/probe.sh` probes the sandbox design;
  - `tests/make-campaign.sh` builds a campaign repository;
  - `tests/toy/` is a tiny campaign with 13 variants, some deliberately broken;
  - `tests/toy-mathlib/` measures timing with Mathlib.
- **Next:** `docs/TEST_PLAN.md`, phases 0–2, then the build items of `docs/BUILD_PLAN.md`.

## Read first

1. `docs/DESIGN.md`.
2. `docs/SPEC.md`.
3. `docs/TEST_PLAN.md`.

Before changing anything in the design, read why it is the way it is in `docs/DECISIONS.md`.

## Rules

- **The human decides design questions.**
  - If a test contradicts the design, or the design is unclear, stop and ask the human, with a recommendation.
  - Record each answer as the next decision in `docs/DECISIONS.md`; the next number is D99. Then update `docs/SPEC.md`, citing the decision number, and `docs/DESIGN.md`, in plain words without decision numbers.
  - While a question waits, list it under "Open questions" in `docs/DECISIONS.md`.
- **Record test results** in `docs/TEST_RESULTS.md`, including failures that reveal design problems. Never quietly work around a design problem.
- **No complicated code** (D67). Prefer plain files, plain commands, Python 3.11 or later with the standard library where possible, and short programs. `lean-verify` must stay short enough to read.
- **Git:**
  - work on `main`, in small commits with clear messages;
  - never commit build outputs, `.lake/`, caches or installed tools (D65);
  - never commit secrets: passwords, tokens, API keys or login folders.
- **Writing style:** short sentences, lists rather than long paragraphs, and the glossary's terms: "task" (not "node"), "can be attempted" (not "ready"), "depth" (not "critical path"), "sandbox" (not "container").

## The test host

- It is a Linux server reached over SSH.
  - Run `scripts/setup-host.sh` as root once.
  - Then work as the campaign user `lean`, logged in over SSH, so that the systemd user session that `systemd-run --user` needs exists.
- **Credentials:** never write the host's password into the repository, commit messages or logs; use SSH keys.
- **Model access:** the human uses subscriptions (Claude, ChatGPT), not API keys. Agent-tool Provers and Fixers log in once per campaign through dedicated login folders (D62, D88). For any test that needs a model, ask the human to log in.

## Points to settle early

- **Is `lake comparator` fast enough per task (D94)?** Measure it with `tests/toy-mathlib` and report to the human.
- **Definitionally equal restatements:** does `lake comparator` accept a statement that is definitionally equal to the approved one but written differently? The `restated-defeq` variant tests this. If the comparator rejects it, the per-task check (SPEC section 7, which accepts definitional equality) must apply the same rule. Otherwise Provers would pass the check and then fail `lean-verify`. Report the result to the human.
