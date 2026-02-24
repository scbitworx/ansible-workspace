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

LOCK_FILE="/var/lock/ansible-pull.lock"
LOG_FILE="/var/log/ansible-pull.log"
REPO="{{ controller_repo_url }}"
INVENTORY="inventory/hosts.yml"
PLAYBOOK="local.yml"

# Append all output to the log file with timestamps.
exec >> "$LOG_FILE" 2>&1
echo "--- ansible-pull started: $(date --iso-8601=seconds) ---"

# Use flock to prevent parallel runs.
exec /usr/bin/flock --nonblock "$LOCK_FILE" \
  /usr/bin/ansible-pull \
    -U "$REPO" \
    -i "$INVENTORY" \
    --limit "$(hostname)" \
    -o \
    "$PLAYBOOK"
```

**What the wrapper provides:**

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

All hosts currently run Arch Linux. Until `jupiter` is migrated to a
stable-release distribution, all hosts use manual invocation only.

- **All hosts (currently Arch Linux):** manual invocation only. Arch's rolling
  release can require manual intervention, so unattended updates are unsafe.
- **Future (stable-release servers):** the `server` role will use
  `ansible.builtin.cron` to schedule periodic runs.

**Why cron, not systemd timers:** Cron is available on virtually all Unix
systems, and `ansible.builtin.cron` provides a single declarative task with
built-in idempotency. No need to template `.service` + `.timer` files.

**Cron job ownership:** The cron job is owned by the `server` role, not the
controller repo. The cron job calls the wrapper script by path.

```yaml
- name: Schedule ansible-pull via cron
  ansible.builtin.cron:
    name: "ansible-pull"
    minute: "*/30"
    job: "/usr/local/bin/ansible-pull-wrapper"
    user: root
```

---

## Bootstrap (First Run)

The wrapper script does not exist on a fresh host. For the first run, the
controller includes `scripts/bootstrap.sh`:

```bash
#!/bin/bash
set -euo pipefail

REPO="https://github.com/scbitworx/ansible-controller.git"

# Install Ansible if not present (distro-aware)
if ! command -v ansible-pull &>/dev/null; then
  if command -v pacman &>/dev/null; then
    pacman -Syu --noconfirm ansible
  elif command -v apt-get &>/dev/null; then
    apt-get update && apt-get install -y ansible
  fi
fi

# Run the initial ansible-pull (no wrapper script exists yet)
ansible-pull \
  -U "$REPO" \
  -i inventory/hosts.yml \
  --limit "$(hostname)" \
  local.yml
```

After this first run, `bootstrap.sh` is never used again on that host.
