# Test plan

Phases 0–2 test what exists now. Phase 3 is the build.

Record every result in `docs/TEST_RESULTS.md`: the date, the host, the versions, what was run, the outcome, and anything surprising. A result that contradicts the design goes to the human (see `AGENTS.md`).

## Phase 0: the host

1. As root: `bash scripts/setup-host.sh`. Add `--agents` before testing agent tools. Every check should print `ok`.
2. Record the versions: distribution, kernel, bubblewrap, systemd, Python, tinyproxy, socat.

## Phase 1: what the design assumes about the host

Work as the user `lean`, logged in over SSH.

1. **The sandbox** (SPEC 12.1–12.2, D95, D96): run `bash tests/sandbox/probe.sh`. Every line should print `ok`. A failing line is a design finding.
2. **Memory per attempt** (D18). This sets N and the memory cap.
   - Build the Mathlib toy campaign (phase 2, step 3).
   - In it, compile the task file inside a memory-capped scope and read its peak:
     ```
     systemd-run --user --scope -p MemoryMax=16G bash -c \
       'lake env lean ToyM/Main.lean; cat /sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup)/memory.peak'
     ```
   - Repeat with 2, 4 and 8 at once. Compiled Mathlib files are shared through memory mapping, so the total should grow much less than linearly. Record what it does.
3. **Loogle, locally** (D79):
   - build Loogle (github.com/nomeata/loogle) against the pinned Mathlib;
   - record its memory use and start-up time;
   - run one query.
4. **Agent tools in a sandbox** (D64, D86, D88, D96). This needs the human, for the subscription logins.
   - Log in once into a dedicated folder: `CLAUDE_CONFIG_DIR=<folder> claude`, and `CODEX_HOME=<folder> codex`.
   - Run each tool non-interactively inside a sandbox, with the proxy bridge of `probe.sh` and its prompt installed as `CLAUDE.md` or `AGENTS.md`.
   - Confirm that it answers, cannot read outside its workspace, cannot use web search (ask it to search), and that two sandboxes can share one login at the same time.
   - Record the exact command-line flags that work; the adapters will need them.
5. **Optional** (the premise of D72): confirm that an `initialize` in an imported module runs in the importing `lean` process.

## Phase 2: `lean-verify`

1. **Unit tests:** `python3 -m unittest discover -s verify`. These test the Git checks and need no Lean.
2. **The toy campaign:** `bash tests/toy/run-cases.sh`.
   - Every variant should match its `expect` file.
   - The `restated-defeq` variant is marked "observe": record whether `lake comparator` accepts a statement that is definitionally equal to the approved one but written differently. Tell the human (see `AGENTS.md`).
   - `--paranoid` also runs the extra checkers bundled with Lean. If they are missing, record that, and run again with `LEAN_VERIFY_ARGS=--no-paranoid`.
   - These parts of `lean_verify.py` have never run and may need fixes. Keep the program short when fixing them:
     - the generated Lean report script (`REPORT`);
     - adding the `LeanVerify` library to `lakefile.toml`;
     - the call to `lake comparator`.
3. **Mathlib timing** (D94). Each copy of Mathlib takes about 7 GB, so keep it on disk: on some hosts `/tmp` is in memory (Ubuntu 26.04).
   ```
   export TMPDIR=~/tmp; mkdir -p $TMPDIR
   bash tests/make-campaign.sh tests/toy-mathlib ~/toym
   time python3 verify/lean_verify.py ~/toym HEAD
   ```
   - Record the time taken by `lake exe cache get`, by the build of the stubs, and by `lake comparator`, with and without `--paranoid`.
   - Tell the human whether the comparator is fast enough to run for every task. For comparison, `check_time_limit` is 600 seconds.

## Phase 3: the build

Follow `docs/BUILD_PLAN.md`. Every piece gets its own tests.
- **The acceptance checker** gets a good file and a bad file for each rule in SPEC section 7. The toy variants are a start.
- **The Runner's first campaign** is the toy campaign.
- **The pilot campaign** (BUILD_PLAN item 11) needs the human, for the model logins and the choice of theorem.
