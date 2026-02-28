# Testing Strategy — Detailed Reference

This document covers all testing for the project: Molecule configuration,
Docker and Vagrant scenarios, Testinfra patterns, CI pipeline, and host
prerequisites.

---

## Overview

Testing is split into two tiers, both managed by Molecule:

| Tier | Driver | Where it runs | What it validates |
|------|--------|---------------|-------------------|
| **Docker scenario** (default) | Docker containers | CI (GitHub Actions) + test-runner sidecar | Role logic: packages, users, config files, templates, idempotency |
| **Vagrant scenario** (integration) | Vagrant + libvirt VM | Developer workstation only | Real kernel, real `systemd`, real package manager, service life cycle |

Both scenarios share the same Testinfra test suite. Tests that require a
real VM are marked `@pytest.mark.vm_only` and automatically skipped in
Docker.

A third tier — **controller integration testing** — validates the full
`ansible-pull` pipeline (bootstrap, vault decryption, role convergence) using
disposable virsh VMs managed by the controller repo's shell scripts. That
tier is documented in the controller repo, not here.

---

## Molecule Toolchain

### CI (GitHub Actions)

CI installs the toolchain via `pip` in a fresh runner:

```bash
pip install ansible-core molecule molecule-plugins[docker] pytest-testinfra
ansible-galaxy collection install community.general ansible.posix community.docker
```

### Test-Runner Sidecar (Claude Code Sessions)

The Claude Code container has no Docker socket access. A sidecar container
handles Molecule execution via SSH:

```bash
ssh test-runner "env -C /workspace/ansible-role-<name> molecule test"
```

Both containers share the same `/workspace` bind mount. The test-runner has
Docker access but no credentials; Claude Code has credentials but no Docker
access.

> For sidecar architecture and build instructions, see
> [workspace-setup.md](workspace-setup.md#molecule-testing-test-runner-sidecar)

### Developer Workstation (Vagrant Scenario)

The Vagrant scenario requires a Python virtual environment. System-level `pip`
install is blocked on Arch Linux, and the AUR `molecule-plugins` package has
circular build dependencies. A venv at `~/.virtualenvs/molecule/` avoids
both problems.

**One-time setup:**

```bash
python -m venv ~/.virtualenvs/molecule
source ~/.virtualenvs/molecule/bin/activate
pip install ansible-core ansible-lint yamllint \
  molecule 'molecule-plugins[docker,vagrant]' pytest-testinfra
ansible-galaxy collection install community.general ansible.posix community.docker
```

The `run.sh` wrapper activates the venv automatically — no PATH changes or
shell profile modifications are needed on the host.

**Additional system prerequisites** (Vagrant scenario only):

- `vagrant` package (system)
- `vagrant-libvirt` plugin: `vagrant plugin install vagrant-libvirt`
- `libvirt`/`qemu` running: `systemctl start libvirtd`

Run `molecule/integration/check-prereqs.sh` from the role directory to
verify all prerequisites.

---

## Docker Scenario (Default)

The default scenario runs all three platforms in Docker containers with
`systemd` as PID 1. This is the same approach used by Jeff Geerling, Robert de
Bock, and most community roles.

### Platform Configuration

```yaml
# molecule/default/molecule.yml
driver:
  name: docker
platforms:
  - name: archlinux
    image: archlinux/archlinux:latest
    command: /usr/sbin/init
    tmpfs: [/run, /tmp]
    volumes: ["/sys/fs/cgroup:/sys/fs/cgroup:rw"]
    cgroupns_mode: host
    privileged: true
    pre_build_image: true

  - name: ubuntu
    image: geerlingguy/docker-ubuntu2404-ansible:latest
    # ...same tmpfs/volumes/privileged settings

  - name: debian
    image: geerlingguy/docker-debian12-ansible:latest
    # ...same tmpfs/volumes/privileged settings
```

### Image Choices

**Arch Linux:** Official `archlinux/archlinux:latest`. Rebuilt weekly,
includes `systemd` via the `base` meta package. Does not include Python.
Community alternatives (`artis3n/docker-arch-ansible`) have been archived.

**Ubuntu/Debian:** Jeff Geerling's images (`geerlingguy/docker-*-ansible`).
Maintained for years, used by thousands of roles, de facto community
standard.

### Docker `prepare.yml`

The Arch container requires Python, sudo, and `openssh` before Ansible modules
can run. The `raw` module handles this without needing Python on the target:

```yaml
- name: Prepare Arch Linux container
  hosts: archlinux
  gather_facts: false
  tasks:
    - name: Install Python, sudo, and openssh (Arch)
      ansible.builtin.raw: pacman -Syu --noconfirm python sudo openssh

    - name: Generate SSH host keys (Arch)
      ansible.builtin.raw: ssh-keygen -A

    - name: Start sshd (Arch)
      ansible.builtin.raw: systemctl start sshd
```

Debian/Ubuntu containers need an `apt` cache update, locale support, and `sshd`
started:

```yaml
- name: Prepare Debian/Ubuntu containers
  hosts: debian:ubuntu
  become: true
  tasks:
    - name: Update apt cache
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 600

    - name: Install prerequisite packages
      ansible.builtin.apt:
        name: [locales, openssh-server]
        state: present

    - name: Create privilege separation directory
      ansible.builtin.file:
        path: /run/sshd
        state: directory
        mode: "0755"

    - name: Start sshd (Debian/Ubuntu)
      ansible.builtin.service:
        name: ssh
        state: started
```

**Why start `sshd` in `prepare.yml`:** Roles that deploy `/etc/ssh/sshd_config`
with `validate: sshd -t -f %s` and a handler that restarts `sshd` need the
service already running before converge. Without this, the restart handler
fails.

### What Docker Cannot Test

- Kernel module loading
- Real hardware interaction
- Service life cycle across reboots
- Full system upgrade behavior
- Init system boot sequence

These are covered by the Vagrant scenario.

### Alternate Scenario

The alternate scenario tests non-default role variable values. It runs a
single platform (Arch Docker) to keep it fast. Variables tested:

- `base_pull_timer_enabled: false` — timer units exist but are disabled
- `base_editor: "nano"` — EDITOR/VISUAL set to nano in bashrc
- `base_histsize: 5000` — custom HISTSIZE/HISTFILESIZE
- `base_extra_packages: ["tree"]` — extra package installation
- Single user (`altuser1`) with default sudo settings

Tests live in `molecule/tests_alternate/` (separate from the shared
`molecule/tests/` used by default and integration).

### Shared Test Data (`shared_vars.yml`)

Both the default and integration scenarios use `vars_files:
[../shared_vars.yml]` instead of inline variables. This eliminates
duplication of the `base_admin_users` test data between converge files.

The shared file defines three test users:

| User | Keys | password_hash | sudo_passwordless |
|------|------|---------------|-------------------|
| testuser1 | 2 keys | yes (SHA-512) | yes (default) |
| testuser2 | 1 key | no | yes (default) |
| testuser3 | 1 key | no | no |

---

## Vagrant Scenario (Integration)

The integration scenario boots a real VM via Vagrant + libvirt for tests that
require a full kernel and init system. Currently Arch Linux only (Ubuntu and
Debian VMs planned for Milestone 9).

### Running

```bash
# Check prerequisites
molecule/integration/check-prereqs.sh

# Full test (create, prepare, converge, idempotence, verify, destroy)
molecule/integration/run.sh test

# Fast iteration
molecule/integration/run.sh converge
molecule/integration/run.sh verify
molecule/integration/run.sh destroy
```

Always use `run.sh` — it handles venv activation, the ANSIBLE_LIBRARY
workaround, and nftables forwarding rules.

### Platform Configuration

```yaml
# molecule/integration/molecule.yml
driver:
  name: vagrant
  provider:
    name: libvirt
platforms:
  - name: arch-integration
    box: generic/arch
    memory: 2048
    cpus: 2
    provider_options:
      management_network_name: default
      management_network_address: 192.168.122.0/24
    config_options:
      synced_folder: false
```

**Network:** The `management_network_name: default` setting reuses the
existing `libvirt` default network (`virbr0`) instead of letting
`vagrant-libvirt` create its own (`virbr1`). Creating a separate network fails
on systems where Docker's nftables rules interfere with libvirt network
creation.

### Vagrant `prepare.yml`

The `generic/arch` Vagrant box ships without Python and with a stale pacman
keyring. The prepare phase handles both:

```yaml
# Play 1: Bootstrap Python (no Python available yet)
- name: Bootstrap Python on Arch Linux VM
  hosts: all
  gather_facts: false
  become: true
  tasks:
    - name: Install Python and update keyring (raw)
      ansible.builtin.raw: |
        pacman -Sy --noconfirm python archlinux-keyring
        pacman-key --populate archlinux

# Play 2: Full upgrade and preconditions (Python now available)
- name: Prepare Arch Linux VM
  hosts: all
  become: true
  tasks:
    - name: Full system upgrade
      ansible.builtin.pacman:
        upgrade: true
        update_cache: true

    - name: Create dummy ansible-pull-wrapper for testing
      ansible.builtin.copy:
        dest: /usr/local/bin/ansible-pull-wrapper
        content: |
          #!/bin/bash
          exit 0
        owner: root
        group: root
        mode: "0755"
```

**Why two plays:** The `raw` module does not require Python on the target, so
it can install Python in a `gather_facts: false` play. Once Python is
installed, subsequent plays can use normal Ansible modules.

**Why install `archlinux-keyring` in the raw step:** The box's keyring is too
old to trust current packager signing keys. Installing the updated keyring
package and repopulating before the full upgrade prevents PGP signature
verification failures. This matches the pattern used by dev-sec's
`ansible-collection-hardening`.

**Why a full system upgrade:** On Arch Linux, installing packages without a
full system upgrade (`pacman -Syu`) is a partial upgrade that can cause
shared library mismatches. The prepare phase is the correct place for this —
it brings the test environment to a known-good state without affecting the
role under test.

### Workarounds

The Vagrant scenario requires three workarounds for environment-specific
issues. All are handled automatically by `run.sh`.

#### 1. ANSIBLE_LIBRARY Regression (molecule-plugins #301)

Molecule 25.2.0+ no longer wires the Vagrant driver's module paths into
Ansible's library search path. The `vagrant` module (shipped inside the
`molecule_plugins` Python package) cannot be found during create/destroy.

**Fix:** Set the library path via `provisioner.config_options.defaults.library`
in `molecule.yml`, referencing a `MOLECULE_VAGRANT_PLUGIN_DIR` environment
variable exported by `run.sh`. This matches the pattern used by dev-sec.

```yaml
# molecule.yml
provisioner:
  config_options:
    defaults:
      library: "${MOLECULE_PROJECT_DIRECTORY}/plugins/modules:/usr/share/ansible:${MOLECULE_VAGRANT_PLUGIN_DIR}"
```

```bash
# run.sh
export MOLECULE_VAGRANT_PLUGIN_DIR
MOLECULE_VAGRANT_PLUGIN_DIR="$(python3 -c \
  'import molecule_plugins.vagrant, os; print(os.path.dirname(molecule_plugins.vagrant.__file__))' \
  2>/dev/null || true)"
```

See: <https://github.com/ansible-community/molecule-plugins/issues/301>

#### 2. `nftables` FORWARD Chain (Docker Coexistence)

Docker sets `policy drop` on the `nftables` FORWARD chain and only allows
traffic on Docker bridge interfaces. Traffic from `virbr0` (libvirt's
default bridge) is dropped, preventing VMs from reaching the internet.

**Fix:** `run.sh` checks for and inserts forwarding rules before running
molecule:

```bash
if ! sudo nft list chain ip filter FORWARD 2>/dev/null | grep -q 'iif "virbr0" accept'; then
  sudo nft insert rule ip filter FORWARD iif virbr0 accept
  sudo nft insert rule ip filter FORWARD oif virbr0 ct state established,related accept
fi
```

These rules do not persist across reboots. `run.sh` re-adds them as needed.

#### 3. Stale Vagrant Box Keyring

Covered above in the `prepare.yml` section. The `generic/arch` box's `pacman`
keyring does not include newer Arch Linux packager signing keys.

---

## Testinfra

Both scenarios use Testinfra (pytest-based) as the verifier. Tests live in
`molecule/tests/` and are shared between Docker and Vagrant scenarios.

### Verifier Configuration

```yaml
# In both molecule/default/molecule.yml and molecule/integration/molecule.yml
verifier:
  name: testinfra
  directory: ../tests/
  options:
    v: true
    sudo: true
```

### Test Directory Structure

```text
molecule/tests/                      # shared between default + integration scenarios
  conftest.py                        # fixtures, markers, vm_only skip logic
  test_packages.py                   # base package binary checks
  test_timezone.py                   # /etc/localtime, /etc/locale.conf
  test_sshd.py                       # sshd_config hardening + algorithm directives + vm_only service check
  test_ansible_pull.py               # timer/service units + vm_only running check
  test_unattended_upgrades.py        # Debian/Ubuntu only, skipped on Arch
  test_users.py                      # per-user checks (parameterized)

molecule/tests_alternate/            # alternate scenario only (non-default variable values)
  conftest.py                        # minimal
  test_timer_disabled.py             # timer units exist but disabled
  test_custom_vars.py                # editor=nano, histsize=5000, tree, altuser1
```

### Shared Fixtures (`conftest.py`)

```python
@pytest.fixture()
def admin_group(host):
    """Return the OS-appropriate admin group name."""
    if host.system_info.distribution in ("arch", "archlinux"):
        return "wheel"
    return "sudo"

@pytest.fixture(
    params=[
        {"name": "testuser1", "expected_keys": [...], "password_hash": True, "sudo_passwordless": True},
        {"name": "testuser2", "expected_keys": [...], "password_hash": False, "sudo_passwordless": True},
        {"name": "testuser3", "expected_keys": [...], "password_hash": False, "sudo_passwordless": False},
    ],
    ids=["testuser1", "testuser2", "testuser3"],
)
def test_user(request):
    """Parameterized fixture yielding each test user dict."""
    return request.param
```

### VM-Only Tests

Tests that require a real VM use the `@pytest.mark.vm_only` marker.
`conftest.py` skips these when `MOLECULE_DRIVER_NAME == "docker"`:

```python
def is_docker():
    return os.environ.get("MOLECULE_DRIVER_NAME", "docker") == "docker"

def pytest_collection_modifyitems(config, items):
    if is_docker():
        skip_docker = pytest.mark.skip(reason="VM-only test, skipping on Docker")
        for item in items:
            if "vm_only" in item.keywords:
                item.add_marker(skip_docker)
```

Example usage:

```python
@pytest.mark.vm_only
def test_sshd_service_running(host):
    assert host.service("sshd").is_running

@pytest.mark.vm_only
def test_ansible_pull_timer_running(host):
    assert host.service("ansible-pull.timer").is_running
```

### Distro-Conditional Tests

Tests that only apply to certain distributions use `pytest.skip()` inside
the test function. Do **not** use module-level `pytestmark` with `skipif` —
the `host` fixture is not available at module scope.

```python
# Correct: skip inside the test
def test_unattended_upgrades_installed(host):
    if host.system_info.distribution not in ("ubuntu", "debian"):
        pytest.skip("Unattended-upgrades only applies to Debian/Ubuntu")
    assert host.package("unattended-upgrades").is_installed

# Wrong: host fixture unavailable at module level
# pytestmark = pytest.mark.skipif(host.system_info..., ...)
```

### Testinfra Patterns and Gotchas

| Pattern | Notes |
|---------|-------|
| `host.file().contains()` | Uses regex — escape special characters (e.g., `r"\*\.conf"`) |
| `host.file().linked_to` | Returns absolute path, not relative |
| `host.user()` | Provides `.groups`, `.shell`, `.home`, `.exists` |
| `host.run()` | For commands not covered by built-in modules |
| Password hash in `molecule.yml` | `$` characters are interpreted as placeholders by Molecule's config parser — keep password hashes in `converge.yml` or `shared_vars.yml` instead |

### Test Counts

| Scenario | Passed | Skipped | Why skipped |
|----------|--------|---------|-------------|
| Docker default (3 platforms) | 326 | 10 | vm_only tests (6) + unattended-upgrades on Arch (4) |
| Docker alternate (Arch only) | 8 | 0 | — |
| Vagrant (Arch VM) | 108 | 4 | unattended-upgrades on Arch |

---

## Precondition Handling

Because roles are standalone (no `meta/main.yml` dependencies), each role's
`prepare.yml` sets up minimal preconditions — the same way test fixtures
simulate external state.

```yaml
# Example: prepare.yml for an extension role
- hosts: all
  become: true
  tasks:
    - name: Simulate base role - create service user
      ansible.builtin.user:
        name: testuser

    - name: Simulate server role - install expected packages
      ansible.builtin.package:
        name: [curl, rsync]
        state: present
```

**What belongs in `prepare.yml`:** Only the specific preconditions the role
under test relies on — user accounts, directories, packages, config files.

**What does NOT belong in `prepare.yml`:** The entire parent role's task
list. `prepare.yml` is a test fixture, not a role runner.

---

## Vault-Encrypted Variables

Molecule tests use **plaintext values**, not vault-encrypted ones. There is
no `pass` or GPG setup in `prepare.yml`.

**Why:** Molecule tests validate role logic (does the user module set the
right password hash, does the template render correctly). Vault decryption is
an orthogonal concern at the `ansible-pull` layer.

| Molecule tests cover | Controller integration tests cover |
|---------------------|------------------------------------|
| Plaintext `password_hash` passed to user module | Full vault decryption via `--vault-id` |
| `/etc/shadow` contains expected hash format | Bootstrap with vault-encrypted inventory |
| Omitted `password_hash` leaves account locked | End-to-end: encrypted hash → decrypted → set in shadow |

---

## CI Pipeline

GitHub Actions runs lint and Docker Molecule tests on every push and PR to
main. The Vagrant scenario runs on the developer workstation only — it
requires `libvirt`/`qemu` and takes longer.

```yaml
# .github/workflows/ci.yml
jobs:
  lint:
    steps:
      - pip install 'ansible-core>=2.17,<2.18' 'ansible-lint>=25,<26' 'yamllint>=1,<2'
      - ansible-galaxy collection install community.general ansible.posix
      - yamllint .
      - ansible-lint

  molecule:
    needs: lint
    steps:
      - pip install 'ansible-core>=2.17,<2.18' 'molecule>=25,<26'
          'molecule-plugins[docker]>=25,<26' 'pytest-testinfra>=10,<11'
      - ansible-galaxy collection install community.general ansible.posix community.docker
      - molecule test                  # default scenario (3 platforms)
      - molecule test -s alternate     # alternate scenario (Arch only)
```

### Required Collections

| Collection | Why |
|------------|-----|
| `community.general` | `pacman` module, `timezone` module, `locale_gen` module |
| `ansible.posix` | `authorized_key` module |
| `community.docker` | Molecule Docker driver (CI only) |

---

## Inspecting Test Environments

```bash
# Docker: converge and keep containers running
molecule converge
molecule login -h archlinux
molecule verify
molecule destroy

# Vagrant: converge and keep VM running
molecule/integration/run.sh converge
# SSH into the VM:
#   vagrant ssh -- from the molecule ephemeral directory
molecule/integration/run.sh verify
molecule/integration/run.sh destroy
```

Use `converge` (not `test`) during development to keep instances alive for
debugging. `test` destroys everything on completion or failure.

---

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Verifier | Testinfra (pytest) | Structured assertions, parameterized tests, better failure output than Ansible assert |
| Test sharing | Single `molecule/tests/` directory | Avoids duplicating tests between Docker and Vagrant scenarios |
| VM-only marker | `@pytest.mark.vm_only` | Clean separation without separate test files |
| Vagrant venv | `~/.virtualenvs/molecule/` | System pip blocked on Arch, AUR has circular deps |
| Wrapper script | `run.sh` | Encapsulates venv activation, workarounds, and nftables — no host PATH changes |
| Arch Docker image | Official `archlinux/archlinux:latest` | No third-party dependency risk |
| ANSIBLE_LIBRARY fix | `config_options.defaults.library` | Matches dev-sec pattern; native Ansible config rather than env var override |
| Libvirt network | Reuse `default` (virbr0) | Avoids vagrant-libvirt creating virbr1, which fails with Docker's nftables |
| Full upgrade in prepare | `pacman -Syu` in VM prepare only | Test environment concern, not role concern; prevents partial upgrade breakage |
