#!/usr/bin/env python3
"""lean-verify: independently check a campaign commit (SPEC.md section 12.3).

    lean-verify REPO COMMIT [--tag approved] [--no-paranoid] [--keep]

Steps:
  1. Git checks against the approval tag (D69, D93): the same top-level
     entries, every file the approval covers unchanged, and covered files
     importing only definition entries and dependency packages.
  2. A clean checkout of COMMIT in a temporary folder.
  3. Mathlib's published build cache, if the project uses Mathlib (network).
  4. The assumptions report, from a build of the approved stubs only (D70).
     The stubs and the files they import are approved, so building them is safe.
  5. `lake comparator --paranoid` on the top-level theorems (D92). It builds the
     project in its own sandbox and replays the proofs through the kernel.

Exit code: 0 verified, 1 not verified, 2 could not run.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

AXIOMS = ["propext", "Classical.choice", "Quot.sound"]
PINS = ["lakefile.toml", "lean-toolchain", "lake-manifest.json"]
MIN_LEAN = (4, 35, 0)


class NotVerified(Exception):
    """A check failed."""


class CannotRun(Exception):
    """lean-verify could not carry out its checks."""


def git(repo, *args):
    r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True)
    if r.returncode != 0:
        raise CannotRun(f"git {' '.join(args)}: {r.stderr.strip()}")
    return r.stdout


class Snapshot:
    """The files of one commit, read through Git."""

    def __init__(self, repo, rev):
        self.repo = repo
        self.rev = git(repo, "rev-parse", "--verify", f"{rev}^{{commit}}").strip()
        self.blobs = {}
        for item in git(repo, "ls-tree", "-r", "-z", "--full-tree", self.rev).split("\0"):
            if item:
                meta, path = item.split("\t", 1)
                self.blobs[path] = meta.split()[2]

    def read(self, path):
        return git(self.repo, "cat-file", "blob", self.blobs[path])

    def entries(self):
        result = {}
        for path in sorted(self.blobs):
            if path.startswith("graph/") and path.endswith(".toml"):
                entry = tomllib.loads(self.read(path))
                result[entry["id"]] = entry
        return result


def strip_comments(text):
    """Remove Lean comments: `--` to the end of the line, and nested `/- -/`."""
    out, depth, i = [], 0, 0
    while i < len(text):
        if text.startswith("/-", i):
            depth, i = depth + 1, i + 2
        elif depth and text.startswith("-/", i):
            depth, i = depth - 1, i + 2
        elif depth:
            i += 1
        elif text.startswith("--", i):
            end = text.find("\n", i)
            i = len(text) if end < 0 else end
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def imports(text):
    """Module names imported in a Lean file's header."""
    tokens = strip_comments(text).split()
    modules, i = [], 0
    while i < len(tokens):
        if tokens[i] in ("module", "prelude", "public", "private", "meta"):
            i += 1
        elif tokens[i] == "import":
            i += 1
            while i < len(tokens) and tokens[i] in ("all", "runtime"):
                i += 1
            if i < len(tokens):
                modules.append(tokens[i])
                i += 1
        else:
            break
    return modules


def module_path(module):
    return "/".join(module.replace("«", "").replace("»", "").split(".")) + ".lean"


def covered(snap, entries):
    """The approved top-level ids, the files the approval covers, and problems found."""
    by_module = {e["module"]: e for e in entries.values()}
    top = sorted(i for i, e in entries.items() if e.get("top_level"))
    files = {p for p in PINS if p in snap.blobs}
    files |= {f"graph/{i}.toml" for i in top}
    todo = [f"stubs/{i}.lean" for i in top]
    problems, seen = [], set()
    while todo:
        path = todo.pop()
        if path in seen:
            continue
        seen.add(path)
        if path not in snap.blobs:
            problems.append(f"{path} is missing")
            continue
        files.add(path)
        for module in imports(snap.read(path)):
            target = module_path(module)
            if target not in snap.blobs:
                continue  # a dependency package, such as Mathlib
            entry = by_module.get(module)
            if entry is None or entry.get("kind") != "definition":
                problems.append(f"{path} imports {module}, which is not a definition entry")
                continue
            files.add(f"graph/{entry['id']}.toml")
            todo.append(target)
    return top, files, problems


def check_approval(snap, approved):
    """Compare a commit with the approval tag. Returns entries, top-level ids, problems."""
    entries = snap.entries()
    top, files, problems = covered(snap, entries)
    approved_top, approved_files, _ = covered(approved, approved.entries())
    if not top:
        problems.append("there are no top-level entries")
    if top != approved_top:
        problems.append(f"top-level entries differ from the approval: approved {approved_top}, found {top}")
    for path in sorted(files | approved_files):
        if snap.blobs.get(path) != approved.blobs.get(path):
            problems.append(f"{path} has changed since the approval")
    return entries, top, problems


def lean_version(toolchain):
    match = re.search(r"v(\d+)\.(\d+)\.(\d+)", toolchain)
    return tuple(int(x) for x in match.groups()) if match else None


def write_inputs(work, entries, top):
    """Write the challenge, the solution and the comparator's configuration."""
    lib = work / "LeanVerify"
    if lib.exists():
        raise CannotRun("the project already has a LeanVerify folder")
    (lib / "Stubs").mkdir(parents=True)
    stubs = []
    for i in top:
        name = "S_" + re.sub(r"[^A-Za-z0-9]", "_", i)
        shutil.copy(work / "stubs" / f"{i}.lean", lib / "Stubs" / f"{name}.lean")
        stubs.append(f"LeanVerify.Stubs.{name}")
    (lib / "Challenge.lean").write_text("".join(f"import {m}\n" for m in stubs))
    (lib / "Solution.lean").write_text("".join(f"import {entries[i]['module']}\n" for i in top))
    with open(work / "lakefile.toml", "a") as f:
        f.write('\n[[lean_lib]]\nname = "LeanVerify"\n')
    theorems = [f"{entries[i]['namespace']}.{s}" for i in top for s in entries[i]["statements"]]
    config = {"challenge_module": "LeanVerify.Challenge", "solution_module": "LeanVerify.Solution",
              "theorem_names": theorems, "permitted_axioms": AXIOMS}
    (work / "comparator.json").write_text(json.dumps(config, indent=2) + "\n")
    return theorems


REPORT = """import Lean
import LeanVerify.Challenge
open Lean in
#eval show CoreM Unit from do
  let env ← getEnv
  for s in {names} do
    match env.find? s.toName with
    | none => IO.println s!"{{s}}\\tMISSING"
    | some info =>
      let used := " ".intercalate (info.type.getUsedConstants.toList.map toString)
      IO.println s!"{{s}}\\t{{used}}"
"""


def lake(work, *args, capture=False):
    r = subprocess.run(["lake", *args], cwd=work, text=True, capture_output=capture)
    return r.returncode, (r.stdout + r.stderr if capture else "")


def assumptions(work, entries, theorems):
    """For each top-level theorem, the assumptions named in its statement (D70)."""
    code, out = lake(work, "build", "LeanVerify.Challenge", capture=True)
    if code != 0:
        raise NotVerified(f"the approved stubs do not build:\n{out}")
    names = json.dumps(theorems, ensure_ascii=False)
    (work / "LeanVerify" / "Report.lean").write_text(REPORT.format(names=names))
    code, out = lake(work, "env", "lean", "LeanVerify/Report.lean", capture=True)
    if code != 0:
        raise CannotRun(f"the assumptions report failed:\n{out}")
    spaces = [e["namespace"] for e in entries.values() if e.get("assumption")]
    result = {}
    for line in out.splitlines():
        name, _, used = line.partition("\t")
        if name in theorems:
            if used == "MISSING":
                raise NotVerified(f"{name} is not in its approved stub")
            result[name] = sorted({c for c in used.split()
                                   if any(c == s or c.startswith(s + ".") for s in spaces)})
    missing = [t for t in theorems if t not in result]
    if missing:
        raise CannotRun(f"the assumptions report gave no line for {missing}:\n{out}")
    return result


def uses_mathlib(work):
    manifest = json.loads((work / "lake-manifest.json").read_text())
    return any(p.get("name") == "mathlib" for p in manifest.get("packages", []))


def verify(repo, commit, tag, paranoid, keep):
    snap, approved = Snapshot(repo, commit), Snapshot(repo, tag)
    print(f"lean-verify: {repo} at {snap.rev[:12]}, approval tag {tag} at {approved.rev[:12]}")
    if "lean-toolchain" not in snap.blobs:
        raise CannotRun("the project has no lean-toolchain file")
    version = lean_version(snap.read("lean-toolchain"))
    if version is None or version < MIN_LEAN:
        raise CannotRun("lake comparator needs Lean v4.35.0 or later (D92)")
    entries, top, problems = check_approval(snap, approved)
    if problems:
        raise NotVerified("approval check failed:\n  " + "\n  ".join(problems))
    print(f"Approval: {len(top)} top-level entries; the files the approval covers are unchanged.")

    folder = Path(tempfile.mkdtemp(prefix="lean-verify-"))
    work = folder / "checkout"
    try:
        git(folder, "clone", "--quiet", "--no-local", "--no-checkout", str(Path(repo).resolve()), str(work))
        git(work, "checkout", "--quiet", "--detach", snap.rev)
        theorems = write_inputs(work, entries, top)
        if uses_mathlib(work):
            print("Fetching Mathlib's published build cache.")
            if lake(work, "exe", "cache", "get")[0] != 0:
                raise CannotRun("lake exe cache get failed")
        found = assumptions(work, entries, theorems)
        print("Running lake comparator" + (" --paranoid" if paranoid else "") + ".")
        code, _ = lake(work, "comparator", "--config", "comparator.json", *(["--paranoid"] if paranoid else []))
        if code == 2:
            raise CannotRun("lake comparator could not start")
        if code != 0:
            raise NotVerified("lake comparator rejected the solution")
        print("\nTop-level theorems:")
        for name in theorems:
            print(f"  {name}")
            print(f"    assumptions: {', '.join(found[name]) or 'none'}")
        print(f"\nVERIFIED: {snap.rev}")
    finally:
        if keep:
            print(f"Checkout kept at {work}")
        else:
            shutil.rmtree(folder, ignore_errors=True)


def main(argv=None):
    parser = argparse.ArgumentParser(prog="lean-verify", description=__doc__.split("\n")[0])
    parser.add_argument("repo", help="the campaign repository")
    parser.add_argument("commit", help="the commit to verify")
    parser.add_argument("--tag", default="approved", help="the approval tag (default: approved)")
    parser.add_argument("--no-paranoid", action="store_true", help="only Lean's own kernel")
    parser.add_argument("--keep", action="store_true", help="keep the temporary checkout")
    args = parser.parse_args(argv)
    sys.stdout.reconfigure(line_buffering=True)  # keep our lines in order with Lake's output
    try:
        verify(args.repo, args.commit, args.tag, not args.no_paranoid, args.keep)
        return 0
    except NotVerified as e:
        print(f"\nNOT VERIFIED: {e}")
        return 1
    except CannotRun as e:
        print(f"\nCOULD NOT RUN: {e}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
