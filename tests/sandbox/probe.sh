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
pids=()
cleanup() { kill "${pids[@]}" 2>/dev/null; rm -rf "$root" "$HOME/.probe-secret"; }
trap cleanup EXIT

# The sandbox of SPEC.md 12.1: host system read-only; home, /root, /run, /var and /tmp hidden;
# the workspace writable; the build cache read-only with a private layer; no network.
sandbox() {
  local unit=$1; shift
  systemd-run --user --scope --quiet --unit="$unit" -p MemoryMax="$mem" -p MemorySwapMax=0 \
    bwrap --die-with-parent --unshare-all --new-session \
      --ro-bind / / --tmpfs /home --tmpfs /root --tmpfs /run --tmpfs /var --tmpfs /tmp \
      --proc /proc --dev /dev \
      --ro-bind "$HOME/.elan" "$HOME/.elan" \
      --bind "$ws" /work --overlay-src "$cache" --tmp-overlay /cache \
      "${extra[@]}" \
      --setenv HOME "$HOME" --setenv PATH "$HOME/.elan/bin:/usr/bin:/bin" --chdir /work \
      "$@"
}
extra=()
n=0
expect() {  # expect ok|fail DESCRIPTION COMMAND...
  local want=$1 what=$2; shift 2
  n=$((n + 1))
  if sandbox "probe-$$-$n" "$@" >/dev/null 2>&1; then got=ok; else got=fail; fi
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

# Agent sandboxes (D96): tinyproxy on the host allows one host; a Unix socket carries the
# connection into the sandbox, where socat exposes it on the sandbox's own loopback.
cat > "$root/tinyproxy.conf" <<EOF
Port 8888
Listen 127.0.0.1
Timeout 60
ConnectPort 443
FilterDefaultDeny Yes
FilterType ere
Filter "$root/allowed"
EOF
printf '^example\\.com$\n' > "$root/allowed"
tinyproxy -d -c "$root/tinyproxy.conf" >"$root/tinyproxy.log" 2>&1 & pids+=($!)
socat "UNIX-LISTEN:$root/proxy.sock,fork" TCP:127.0.0.1:8888 & pids+=($!)
sleep 2
extra=(--bind "$root/proxy.sock" /proxy.sock)
bridge='socat TCP-LISTEN:3128,bind=127.0.0.1,fork,reuseaddr UNIX-CONNECT:/proxy.sock & sleep 1;'
expect ok   "an agent sandbox reaches the allowed host through the proxy" \
  sh -c "$bridge curl -sS --max-time 15 -x http://127.0.0.1:3128 -o /dev/null https://example.com"
expect fail "an agent sandbox cannot reach any other host" \
  sh -c "$bridge curl -sS --max-time 15 -x http://127.0.0.1:3128 -o /dev/null https://www.wikipedia.org"
expect fail "an agent sandbox cannot bypass the proxy" \
  sh -c "curl -sS --max-time 10 -o /dev/null https://example.com"
