# ansible-pull Workflow — Detailed Reference

This document contains the full details of the `ansible-pull` workflow,
playbook structure, wrapper script, bootstrap process, and scheduling policy.

---

## `local.yml` — Main Playbook

The playbook follows a fixed structure: controller-owned setup tasks first,
then core roles (by group), then host-specific extension roles, then
`dotfiles` last.

```yaml
# --- Controller-owned setup (runs before any roles) ---
- hosts: all
  become: true
  pre_tasks:
    - name: Install roles from requirements.yml
      ansible.builtin.command:
        cmd: ansible-galaxy install -r requirements.yml --force
      delegate_to: localhost
      run_once: true

    - name: Deploy ansible-pull wrapper script
      ansible.builtin.template:
        src: templates/ansible-pull-wrapper.sh.j2
        dest: /usr/local/bin/ansible-pull-wrapper
        owner: root
        group: root
        mode: "0755"

# --- Core roles (applied by group) ---
- hosts: all
  become: true
  roles:
    - scbitworx.base

- hosts: servers
  become: true
  roles:
    - scbitworx.server

- hosts: workstations
  become: true
  roles:
    - scbitworx.workstation

- hosts: laptops
  become: true
  roles:
    - scbitworx.laptop

# --- Host-specific extension roles (examples — will grow over time) ---
- hosts: jupiter
  become: true
  roles:
    - scbitworx.syncthing_server
    - scbitworx.taskchampion_sync_server

- hosts: ceres
  become: true
  roles:
    - scbitworx.darp6
    - scbitworx.devbox
    - scbitworx.hypervisor

- hosts: mars
  become: true
  roles:
    - scbitworx.devbox
    - scbitworx.hypervisor

# --- Dotfiles runs last (user-level config, no privilege escalation) ---
- hosts: all
  become: false
  roles:
    - scbitworx.dotfiles
```

---

## The Wrapper Script

Each host runs `ansible-pull` via a wrapper script deployed to
`/usr/local/bin/ansible-pull-wrapper`. The wrapper is owned by the controller
repo (not any role) because it encapsulates self-knowledge: the controller's
repo URL, inventory path, and playbook name.

```bash
#!/bin/bash
set -euo pipefail

# Re-exec as root if not already.
if [ "$(id -u)" -ne 0 ]; then
  exec sudo "$0" "$@"
fi

LOCK_FILE="/var/lock/ansible-pull.lock"
LOG_FILE="/var/log/ansible-pull.log"
REPO="{{ controller_repo_url }}"
INVENTORY="inventory/hosts.yml"
PLAYBOOK="local.yml"
VAULT_CLIENT="/usr/local/bin/ansible-vault-client"

# Append all output to the log file with timestamps.
exec >> "$LOG_FILE" 2>&1
echo "--- ansible-pull started: $(date --iso-8601=seconds) ---"

# Use flock to prevent parallel runs.
exec /usr/bin/flock --nonblock "$LOCK_FILE" \
  /usr/bin/ansible-pull \
    -U "$REPO" \
    -i "$INVENTORY" \
    --vault-id "scbitworx@${VAULT_CLIENT}" \
    --limit "$(hostname)" \
    -o \
    "$PLAYBOOK"
```

**What the wrapper provides:**

- **Sudo re-exec:** If not running as root, the wrapper re-execs itself via
  `sudo`. This allows admin users (created by `base`) to invoke the wrapper
  directly without prefixing `sudo`.
- **Vault integration:** Passes `--vault-id scbitworx@/usr/local/bin/ansible-vault-client`
  so vault-encrypted inventory values are decrypted automatically.
- **Logging:** All output appended to `/var/log/ansible-pull.log` with
  timestamps.
- **Parallel run inhibition:** `flock --nonblock` ensures only one
  `ansible-pull` process runs at a time.
- **Consistent invocation:** Both cron jobs and manual runs use the same
  script.

**Why the controller owns the wrapper script, not a role:** The wrapper
contains the controller repo URL, inventory path, and playbook name — values
that describe the controller itself. Placing these in a role would create an
inverted dependency.

**Controller variable:** The template uses `controller_repo_url`, defined in
`inventory/group_vars/all.yml`.

---

## Change Detection and Role Fetching

Because every role is pinned to a specific tag in `requirements.yml`, the
controller repo is the **single source of truth** for whether anything has
changed. `ansible-pull -o` (`--only-if-changed`) is sufficient to skip
unnecessary runs.

Role installation (`ansible-galaxy install -r requirements.yml --force`) is
handled inside `local.yml` as a `pre_tasks` step. This ensures roles are only
fetched when `ansible-pull` has already determined that a converge is needed.

---

## Scheduling Policy

The `base` role deploys a systemd timer (`ansible-pull.timer`) that runs the
wrapper script periodically on all hosts. The default interval is
configurable via `base_pull_interval` (default: `4h`) and overridable in
`group_vars/` — e.g., more frequent for servers, less frequent for
workstations.

- **Timer ownership:** The `base` role owns the timer. It runs on all hosts.
- **`Persistent=true`:** Ensures laptops that sleep catch up on wake.
- **`RandomizedDelaySec=5min`:** Spreads load when multiple hosts converge.
- **Safe on Arch:** `ansible-pull` only installs packages with
  `state: present` (no partial upgrades).
- **Toggleable:** Set `base_pull_timer_enabled: false` to disable.

```ini
# ansible-pull.timer (deployed by base role)
[Timer]
OnBootSec=5min
OnUnitActiveSec={{ base_pull_interval }}
Persistent=true
RandomizedDelaySec=5min

[Install]
WantedBy=timers.target
```

---

## Pre-Bootstrap Requirements

Before running `bootstrap.sh`, the operator must set up the vault password
backend on the target host:

1. Install `pass` and `gpg` (distro package manager)
2. Initialize the pass store: `pass init <gpg-key-id>`
3. Add the vault password: `pass insert scbitworx/vault-password`

The bootstrap script validates these prerequisites and exits with a clear
error message if any are missing.

---

## Bootstrap (First Run)

The wrapper script does not exist on a fresh host. For the first run, the
controller includes `scripts/bootstrap.sh`:

```bash
#!/bin/bash
set -euo pipefail

REPO="https://github.com/scbitworx/ansible-controller.git"
VAULT_CLIENT="/usr/local/bin/ansible-vault-client"

# --- Prerequisite checks ---

if ! command -v gpg &>/dev/null; then
  echo "ERROR: gpg is not installed. Install gnupg first." >&2
  exit 1
fi

if ! command -v pass &>/dev/null; then
  echo "ERROR: pass is not installed. Install pass (password-store) first." >&2
  exit 1
fi

if ! pass ls scbitworx/vault-password &>/dev/null; then
  echo "ERROR: pass entry 'scbitworx/vault-password' not found." >&2
  echo "Initialize the pass store and add the vault password:" >&2
  echo "  pass init <gpg-key-id>" >&2
  echo "  pass insert scbitworx/vault-password" >&2
  exit 1
fi

# --- Install Ansible if not present (distro-aware) ---

if ! command -v ansible-pull &>/dev/null; then
  if command -v pacman &>/dev/null; then
    pacman -Syu --noconfirm ansible
  elif command -v apt-get &>/dev/null; then
    apt-get update && apt-get install -y ansible
  fi
fi

# --- Deploy inline vault client (chicken-and-egg: the templated version
#     is deployed by the playbook, but we need it for the first run) ---

cat > "$VAULT_CLIENT" << 'INLINE_CLIENT'
#!/bin/sh
set -eu
PASSWORD=$(pass scbitworx/vault-password 2>/dev/null) || {
  echo "ERROR: Failed to retrieve scbitworx/vault-password from pass" >&2
  exit 1
}
printf '%s' "$PASSWORD"
INLINE_CLIENT
chmod 755 "$VAULT_CLIENT"

# --- Run the initial ansible-pull ---

ansible-pull \
  -U "$REPO" \
  -i inventory/hosts.yml \
  --vault-id "scbitworx@${VAULT_CLIENT}" \
  --limit "$(hostname)" \
  local.yml
```

The bootstrap script deploys an inline vault client before the first
`ansible-pull` run. This solves the chicken-and-egg problem: the inventory may
contain vault-encrypted values, but the full templated vault client is deployed
by the playbook itself. After the first run, the templated version at
`/usr/local/bin/ansible-vault-client` replaces the inline one.

After this first run, `bootstrap.sh` is never used again on that host.

---

## Vault Integration

Vault-encrypted variables flow through `ansible-pull` as follows:

1. The wrapper (or bootstrap) passes `--vault-id scbitworx@/usr/local/bin/ansible-vault-client`
2. Ansible calls the vault client script when it encounters `!vault`-tagged values
3. The vault client retrieves the password from `pass scbitworx/vault-password`
4. Ansible decrypts the values in-memory and uses them normally

The `ansible.cfg` also includes `vault_identity_list` so that local
`ansible-vault` commands (encrypt, decrypt, view) work without manual
`--vault-id` flags on hosts where the client is installed.
