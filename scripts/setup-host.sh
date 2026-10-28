#!/usr/bin/env bash
# Prepare a Linux host for developing and testing the protocol (docs/TEST_PLAN.md, phase 0).
#
#   As root, on Ubuntu 24.04 or Debian 12 or later:
#     bash scripts/setup-host.sh [--agents] [USER]
#
# Installs the packages the protocol needs, creates the campaign user (default: lean),
# installs elan and Lean v4.35.0 for that user, and checks that the sandbox pieces work
# for that user. With --agents it also installs Claude Code and Codex.
# It changes no security settings; when a check fails it says what to do.
set -euo pipefail

agents=0
if [ "${1:-}" = --agents ]; then agents=1; shift; fi
user=${1:-lean}
lean_version=leanprover/lean4:v4.35.0
if [ "$(id -u)" != 0 ]; then echo "setup-host: run as root" >&2; exit 2; fi

echo "== Packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q git curl ca-certificates python3 bubblewrap jq dbus-user-session
if [ "$agents" = 1 ]; then apt-get install -y -q nodejs npm; fi

echo "== User $user"
id -u "$user" >/dev/null 2>&1 || useradd -m -s /bin/bash "$user"
loginctl enable-linger "$user"          # a systemd user manager, needed for systemd-run --user
if [ -f /root/.ssh/authorized_keys ] && [ ! -f "/home/$user/.ssh/authorized_keys" ]; then
  install -d -m 700 -o "$user" -g "$user" "/home/$user/.ssh"
  install -m 600 -o "$user" -g "$user" /root/.ssh/authorized_keys "/home/$user/.ssh/authorized_keys"
fi
uid=$(id -u "$user")
for _ in $(seq 40); do [ -S "/run/user/$uid/bus" ] && break; sleep 0.5; done

as_user() {
  runuser -u "$user" -- env HOME="/home/$user" XDG_RUNTIME_DIR="/run/user/$uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    PATH="/home/$user/.elan/bin:/home/$user/.local/bin:/usr/local/bin:/usr/bin:/bin" bash -c "$1"
}

echo "== Lean"
as_user 'command -v elan >/dev/null || curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y --default-toolchain none'
as_user "elan toolchain install $lean_version"

if [ "$agents" = 1 ]; then
  echo "== Agent tools (check the vendors' current install instructions if this fails)"
  as_user 'command -v claude >/dev/null || curl -fsSL https://claude.ai/install.sh | bash'
  command -v codex >/dev/null || npm install -g @openai/codex
fi

echo "== Checks"
failed=0
log=$(mktemp)
check() {
  local name=$1; shift
  if "$@" >"$log" 2>&1; then echo "ok    $name"; else echo "FAIL  $name"; tail -5 "$log" | sed 's/^/      /'; failed=1; fi
}
check "Python 3.11 or later" python3 -c 'import sys; assert sys.version_info >= (3, 11)'
check "bubblewrap 0.8 or later" bash -c \
  'v=$(bwrap --version | awk "{print \$2}"); [ "$(printf "%s\n0.8.0\n" "$v" | sort -V | head -1)" = 0.8.0 ]'
check "bubblewrap works for $user (unprivileged user namespaces)" \
  as_user 'bwrap --unshare-all --ro-bind / / --proc /proc --dev /dev true'
check "bubblewrap overlay with a private writable layer" as_user \
  'd=$(mktemp -d) && mkdir $d/low && echo x > $d/low/f &&
   bwrap --unshare-all --ro-bind / / --proc /proc --dev /dev --overlay-src $d/low --tmp-overlay /mnt \
     sh -c "echo y > /mnt/g && cat /mnt/f" && [ ! -e $d/low/g ]; s=$?; rm -rf $d; exit $s'
check "systemd user scope with a memory cap" as_user \
  'systemd-run --user --scope --quiet -p MemoryMax=200M -p MemorySwapMax=0 \
     sh -c "cat /sys/fs/cgroup\$(cut -d: -f3 /proc/self/cgroup)/memory.max" | grep -qx 209715200'
check "Lean $lean_version runs" as_user \
  "cd \$(mktemp -d) && echo '#eval 1 + 1' > t.lean && lean +$lean_version t.lean | grep -qx 2"
check "lake comparator is available" as_user "lake +$lean_version help comparator | grep -q 'Judge a solution'"
rm -f "$log"

if [ "$failed" = 1 ] && [ "$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || echo 0)" = 1 ]; then
  echo
  echo "Note: this kernel restricts unprivileged user namespaces through AppArmor."
  echo "If the bubblewrap checks failed, see /etc/apparmor.d/ for a bwrap profile, or ask the human"
  echo "whether to set kernel.apparmor_restrict_unprivileged_userns=0 on this test host."
fi

echo
echo "Next: log in as $user over SSH (so the systemd user session exists) and follow docs/TEST_PLAN.md."
echo "Security: if a password for this host was ever shared in a chat, change it, and once key login"
echo "works, set 'PasswordAuthentication no' in /etc/ssh/sshd_config."
exit "$failed"
