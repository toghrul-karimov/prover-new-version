"""Unit tests for lean-verify's Git checks. They need git and Python only, not Lean.

    python3 -m unittest discover -s verify
"""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import lean_verify as lv

ENV = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
       "GIT_COMMITTER_EMAIL": "t@t", "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_SYSTEM": os.devnull}

FILES = {
    "lean-toolchain": "leanprover/lean4:v4.35.0\n",
    "lakefile.toml": 'name = "toy"\n\n[[lean_lib]]\nname = "Toy"\n',
    "lake-manifest.json": '{"version": "1.1.0", "packagesDir": ".lake/packages", "packages": []}\n',
    "graph/defs.basic.toml": 'id = "defs.basic"\nkind = "definition"\nmodule = "Toy.Defs.Basic"\n'
                             'namespace = "Toy.Defs.Basic"\ndepends = []\nstatements = []\n',
    "graph/lemmas.double.toml": 'id = "lemmas.double"\nkind = "task"\nmodule = "Toy.Lemmas.Double"\n'
                                'namespace = "Toy.Lemmas.Double"\ndepends = ["defs.basic"]\n'
                                'statements = ["double_eq"]\n',
    "graph/main.toml": 'id = "main"\nkind = "task"\nmodule = "Toy.Main"\nnamespace = "Toy.Main"\n'
                       'depends = ["defs.basic", "lemmas.double"]\nstatements = ["main"]\n'
                       'top_level = true\n',
    "Toy/Defs/Basic.lean": "namespace Toy.Defs.Basic\ndef double (n : Nat) : Nat := n + n\nend Toy.Defs.Basic\n",
    "Toy/Lemmas/Double.lean": "import Toy.Defs.Basic\n-- stub\n",
    "Toy/Main.lean": "import Toy.Defs.Basic\n-- stub\n",
    "stubs/lemmas.double.lean": "import Toy.Defs.Basic\n-- stub\n",
    "stubs/main.lean": "/- the top-level statement -/\nimport Toy.Defs.Basic -- definitions\nimport Mathlib.Tactic\n-- stub\n",
}


class Repo:
    def __init__(self, files):
        self.dir = tempfile.TemporaryDirectory()
        self.path = Path(self.dir.name)
        self.git("init", "-q", "-b", "main")
        self.write(files)
        self.commit("approved state")
        self.git("tag", "approved")

    def git(self, *args):
        subprocess.run(["git", "-C", str(self.path), *args], check=True, env=ENV, capture_output=True)

    def write(self, files):
        for name, text in files.items():
            p = self.path / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text)

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "--allow-empty", "-m", message)

    def problems(self):
        snap, approved = lv.Snapshot(self.path, "HEAD"), lv.Snapshot(self.path, "approved")
        return lv.check_approval(snap, approved)[2]


class Imports(unittest.TestCase):
    def test_header_only(self):
        text = "/- doc /- nested -/ -/\nmodule\npublic import A.B -- c\nimport all C import D\ntheorem x : True := trivial\nimport E\n"
        self.assertEqual(lv.imports(text), ["A.B", "C", "D"])

    def test_module_path(self):
        self.assertEqual(lv.module_path("Toy.«Foo».Bar"), "Toy/Foo/Bar.lean")


class Approval(unittest.TestCase):
    def setUp(self):
        self.repo = Repo(FILES)

    def tearDown(self):
        self.repo.dir.cleanup()

    def test_proofs_may_change(self):
        self.repo.write({"Toy/Main.lean": "import Toy.Defs.Basic\nimport Toy.Lemmas.Double\n-- proof\n",
                         "Toy/Lemmas/Double.lean": "import Toy.Defs.Basic\n-- proof\n"})
        self.repo.commit("proofs")
        self.assertEqual(self.repo.problems(), [])

    def test_covered_files(self):
        snap = lv.Snapshot(self.repo.path, "HEAD")
        top, files, problems = lv.covered(snap, snap.entries())
        self.assertEqual(top, ["main"])
        self.assertEqual(problems, [])
        self.assertEqual(files, {"lakefile.toml", "lean-toolchain", "lake-manifest.json", "graph/main.toml",
                                 "stubs/main.lean", "graph/defs.basic.toml", "Toy/Defs/Basic.lean"})

    def assert_rejected(self, files, phrase):
        self.repo.write(files)
        self.repo.commit("change")
        problems = self.repo.problems()
        self.assertTrue(any(phrase in p for p in problems), problems)

    def test_definition_change(self):
        self.assert_rejected({"Toy/Defs/Basic.lean": "namespace Toy.Defs.Basic\ndef double (n : Nat) : Nat := 2\nend Toy.Defs.Basic\n"},
                             "Toy/Defs/Basic.lean has changed")

    def test_stub_change(self):
        self.assert_rejected({"stubs/main.lean": "import Toy.Defs.Basic\n-- weaker\n"}, "stubs/main.lean has changed")

    def test_pin_change(self):
        self.assert_rejected({"lakefile.toml": FILES["lakefile.toml"] + "# x\n"}, "lakefile.toml has changed")

    def test_top_level_entry_change(self):
        self.assert_rejected({"graph/main.toml": FILES["graph/main.toml"].replace('["main"]', '["main", "extra"]')},
                             "graph/main.toml has changed")

    def test_new_top_level_entry(self):
        self.assert_rejected({"graph/lemmas.double.toml": FILES["graph/lemmas.double.toml"] + "top_level = true\n"},
                             "top-level entries differ")

    def test_stub_importing_a_task(self):
        self.assert_rejected({"stubs/main.lean": "import Toy.Defs.Basic\nimport Toy.Lemmas.Double\n"},
                             "imports Toy.Lemmas.Double, which is not a definition entry")


if __name__ == "__main__":
    unittest.main()
