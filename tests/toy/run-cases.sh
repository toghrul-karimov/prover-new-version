#!/usr/bin/env bash
# Build the toy campaign once per variant and run lean-verify on each; compare the exit code
# with variants/<name>/expect (0 verified, 1 not verified, "observe": record what happens).
# Usage: run-cases.sh [VARIANT...]   Environment: OUT (log folder), LEAN_VERIFY_ARGS.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=${OUT:-$(mktemp -d "${TMPDIR:-/tmp}/toy-cases.XXXXXX")}
mkdir -p "$out"
names=("$@")
if [ ${#names[@]} -eq 0 ]; then
  names=(); for v in "$here"/variants/*/; do names+=("$(basename "$v")"); done
fi
failures=0
for name in "${names[@]}"; do
  v="$here/variants/$name"
  expect=$(cat "$v/expect")
  if ! "$here/../make-campaign.sh" "$here" "$out/$name" "$v" > "$out/$name.make.log" 2>&1; then
    echo "ERROR   $name: could not build the campaign (see $out/$name.make.log)"
    failures=$((failures + 1)); continue
  fi
  start=$(date +%s)
  # shellcheck disable=SC2086
  python3 "$here/../../verify/lean_verify.py" ${LEAN_VERIFY_ARGS:-} "$out/$name" HEAD > "$out/$name.verify.log" 2>&1
  code=$?
  secs=$(( $(date +%s) - start ))
  if [ "$expect" = observe ]; then
    echo "OBSERVE $name: exit $code in ${secs}s; record it in docs/TEST_RESULTS.md (log: $out/$name.verify.log)"
  elif [ "$code" = "$expect" ]; then
    echo "ok      $name: exit $code in ${secs}s"
  else
    echo "FAIL    $name: exit $code, expected $expect (log: $out/$name.verify.log)"
    failures=$((failures + 1))
  fi
done
echo "Logs: $out"
[ "$failures" -eq 0 ]
