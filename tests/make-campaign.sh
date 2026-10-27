#!/usr/bin/env bash
# Build a campaign repository the way a campaign would (docs/TEST_PLAN.md):
#   1. the Planner's files from SRC/planner; each task file starts as a copy of its stub;
#   2. VARIANT/before, if any; commit; the approval tag `approved`;
#   3. the Provers' files from SRC/provers; commit;
#   4. VARIANT/after and VARIANT/after.sh, if any; commit.
# Needs git and lake (through elan). Usage: make-campaign.sh SRC DEST [VARIANT]
set -euo pipefail
src=$(cd "$1" && pwd)
dest=$2
variant=""
if [ $# -ge 3 ]; then variant=$(cd "$3" && pwd); fi
if [ -e "$dest" ]; then echo "make-campaign: $dest already exists" >&2; exit 2; fi

copy() { if [ -d "$1" ]; then cp -r "$1/." .; fi; }

mkdir -p "$dest"
cp -r "$src/planner/." "$dest/"
cd "$dest"
for stub in stubs/*.lean; do
  id=$(basename "$stub" .lean)
  module=$(sed -n 's/^module = "\(.*\)"$/\1/p' "graph/$id.toml")
  file="${module//.//}.lean"
  mkdir -p "$(dirname "$file")"
  cp "$stub" "$file"
done
lake update                      # writes lake-manifest.json; fetches Mathlib if required
if [ ! -f lake-manifest.json ]; then echo "make-campaign: lake update wrote no manifest" >&2; exit 2; fi

git init -q -b main
git config user.name "toy campaign"
git config user.email "toy@example.invalid"
if [ -n "$variant" ]; then copy "$variant/before"; fi
git add -A
git commit -q -m "Planner: definitions and stubs"
git tag approved
copy "$src/provers"
git add -A
git commit -q -m "Provers: proofs"
if [ -n "$variant" ]; then
  copy "$variant/after"
  if [ -f "$variant/after.sh" ]; then bash "$variant/after.sh"; fi
  git add -A
  git commit -q --allow-empty -m "Variant: $(basename "$variant")"
fi
echo "$dest"
