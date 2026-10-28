#!/usr/bin/env bash
# Probe the attempt sandbox of SPEC.md section 12 on this host (docs/TEST_PLAN.md, phase 1).
# Run as the campaign user (not root), from an SSH login, so the systemd user session exists.
# Each line prints "ok" or "FAIL"; record the results in docs/TEST_RESULTS.md.
#   Environment: MEM (memory cap, default 1G), LEAN (toolchain, default leanprover/lean4:v4.35.0).
set -uo pipefail
mem=${MEM:-1G}
lean=${LEAN:-leanprover/lean4:v4.35.0}
root=$(mktemp -d)
ws=$root/work cache=$root/cache
mkdir -p "$ws" "$cache"
echo cached > "$cache/file"
echo secret > "$HOME/.probe-secret"
cleanup() { rm -rf "$root" "$HOME/.probe-secret"; }
trap cleanup EXIT

# The sandbox of SPEC.md 12.1: only the system folders /usr and /etc, read-only (home folders,
# /run, /var and the rest are not there); the workspace writable; the build cache read-only with
# a private layer; no network (agent sandboxes: see the end). The root is bwrap's own empty folder, not the host's, so that bwrap
# can create /work and the other mount points (with `--ro-bind / /` it cannot). Needs merged /usr.
sandbox() {
  local unit=$1; shift
  systemd-run --user --scope --quiet --unit="$unit" -p MemoryMax="$mem" -p MemorySwapMax=0 \
    bwrap --die-with-parent --unshare-all --new-session \
      --ro-bind /usr /usr --ro-bind /etc /etc \
      --symlink usr/bin /bin --symlink usr/sbin /sbin --symlink usr/lib /lib --symlink usr/lib64 /lib64 \
      --tmpfs /tmp --proc /proc --dev /dev \
      --ro-bind "$HOME/.elan" "$HOME/.elan" \
      --bind "$ws" /work --overlay-src "$cache" --tmp-overlay /cache \
      "${extra[@]}" \
      --setenv HOME "$HOME" --setenv PATH "$HOME/.elan/bin:/usr/bin:/bin" --chdir /work \
      "$@"
}
extra=()
n=0
# Inside the sandbox a failing command exits 3, so that a sandbox that did not start
# is never taken for a command the sandbox blocked. A signal (128 or more) also counts as
# failing: when the memory cap is hit, systemd stops the whole scope.
expect() {  # expect ok|fail DESCRIPTION COMMAND...
  local want=$1 what=$2; shift 2
  n=$((n + 1))
  sandbox "probe-$$-$n" sh -c '"$@" || exit 3' sh "$@" >/dev/null 2>&1
  local code=$?
  if [ $code = 0 ]; then got=ok
  elif [ $code = 3 ] || [ $code -ge 128 ]; then got=fail
  else echo "FAIL  $what (the sandbox did not start)"; return
  fi
  if [ "$got" = "$want" ]; then echo "ok    $what"; else echo "FAIL  $what (command ${got}ed)"; fi
}

expect ok   "the workspace is writable"                 sh -c 'echo x > /work/written'
[ -f "$ws/written" ] && echo "ok    the host sees the workspace file" || echo "FAIL  the host sees the workspace file"
expect fail "system folders are read-only"              sh -c 'echo x > /usr/probe'
expect fail "home folders are hidden"                   cat "$HOME/.probe-secret"
expect fail "the user's runtime folder (/run/user) is hidden" ls "/run/user/$(id -u)/bus"
expect fail "no network"                                python3 -c 'import socket; socket.create_connection(("1.1.1.1", 443), 3)'
expect ok   "the cache is readable, with a private writable layer" sh -c 'echo y > /cache/new && cat /cache/file'
[ ! -e "$cache/new" ] && echo "ok    writes to the cache stay private" || echo "FAIL  writes to the cache stay private"
expect fail "the memory cap ($mem) stops a process that needs more" python3 -c 'b = b"x" * (2 * 1024 ** 3)'
expect ok   "Lean runs inside, with elan read-only"     lean "+$lean" --version

# Stopping the scope ends every process in it (D43).
sandbox "probe-$$-stop" sleep 300 >/dev/null 2>&1 &
sleep 2
systemctl --user stop "probe-$$-stop.scope" 2>/dev/null
sleep 1
if pgrep -u "$(id -u)" -f "^sleep 300$" >/dev/null; then echo "FAIL  stopping the scope ends its processes"; else echo "ok    stopping the scope ends its processes"; fi

# Agent sandboxes (D99): the host's network, without restriction. /run stays hidden except the
# DNS resolver's folder, where /etc/resolv.conf points (/run/systemd/resolve on Ubuntu).
resolver=$(dirname "$(readlink -f /etc/resolv.conf)")
extra=(--share-net)
case $resolver in /run/*) extra+=(--ro-bind "$resolver" "$resolver") ;; esac
expect ok   "an agent sandbox reaches a host by name"   curl -sS --max-time 15 -o /dev/null https://example.com
expect fail "an agent sandbox still hides home folders" cat "$HOME/.probe-secret"
