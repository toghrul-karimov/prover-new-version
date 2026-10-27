# Optional rewrite after a campaign

This brief is for whoever does the rewrite: the Planner, if you task it, or a new agent you start from your own machine. The step is optional. A campaign's certified result is its last verified commit. The rewrite only makes the project easier to read, reuse and maintain.

## What must not change

- **The certified result.** Never modify the campaign's verified commit; work on a new branch. If the rewrite cannot be completed, the verified commit remains the result.
- **What is proved.** Approved top-level statements and definitions keep their meaning. Every top-level theorem in the rewritten project must still give its approved statement. Where a theorem is renamed or restated, add a short proof that the new version gives the approved one.
- **The rules of acceptance.** The only allowed axioms are `propext`, `Classical.choice` and `Quot.sound`, and there is no `sorry`.

## The job, in order

1. **Ask the human whether to upgrade Lean and Mathlib.** Never assume.
2. **Write a plan:** the topic layout of the files, the new names, which helpers to merge or replace, and which long proofs to split. Show it to the human before starting, if they want to see it.
3. **If upgrading:**
   - If the version gap is large, upgrade in steps through intermediate versions. That way Mathlib's deprecation warnings, which name the replacement, still guide each rename.
   - Carry the top-level statements over first, changing only what the upgrade forces, and get the human's approval for them again.
4. **Rewrite**, following the sections below.
5. **Heartbeat pass:** remove each `maxHeartbeats` raise in turn, rebuild, and keep only the raises that are needed.
6. **`verify`** the final commit, against the approved (or re-approved) statements.

## What to improve

- **Layout and names.**
  - Group files by mathematical topic, not by task or order of work.
  - Use descriptive Mathlib-style names; no task identifiers in public names.
  - Give each file a module docstring.
- **Duplicates.**
  - Merge helper lemmas proved in several files into one shared lemma.
  - Replace helpers that Mathlib already has. Run `exact?` on each helper's statement to find them.
  - In Baker, `Finset.prod_le_prod₀` was re-proved by induction in 7 files.
- **Statements.** State theorems directly, with their hypotheses. Replace long conjunctions, which force positional access like `(h …).2.2.1`, with separate named theorems.
- **Proofs.**
  - Split long proofs into named lemmas.
  - Replace fragile patterns. The commonest is a plain `simp` whose reshaped goal a later `rw` or `exact` depends on; use `simp only [...]` instead.
  - Avoid file-level `open Classical`, and remove unused hypotheses.
- **Warnings and linters.**
  - Fix deprecation warnings.
  - Run Mathlib's linters (`#lint`) where useful.
  - For the final check, warnings can be treated as errors (`set_option warningAsError true`).
- **Documentation.** Write docstrings for public definitions and main theorems. Keep the target sheets in line with the final names.

## How to run it

- **Through the Runner** (recommended for a large project). Each file's rewrite is submitted as a task, carried out by a Prover with a rewrite prompt, and checked by the Runner against the approved statements. The work runs in parallel and is recorded as usual. Whoever does the rewrite writes the plan and submits the tasks.
- **Directly** (fine for a small project). The agent rewrites the files itself; `verify` at the end is still required.

Either way, record who rewrote each file, in receipts or commit messages, so authorship stays clear.

## Afterwards

- Add to the lessons file what the rewrite found, for example recurring kinds of duplicate or fragile proofs, so the next protocol revision can prevent them.
- **If the goal is a contribution to Mathlib,** expect more work than this rewrite. Mathlib's reviewers often ask for more general definitions and a different structure, so plan for human-guided rework.
