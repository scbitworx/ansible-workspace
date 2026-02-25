# Molecule Testing Strategy — Detailed Reference

This document contains the full Molecule testing configuration, Docker image
choices, and precondition handling patterns.

---

## Docker-Only Testing

All Molecule testing uses Docker containers with systemd running as PID 1.
This is the same approach used by Jeff Geerling and Robert de Bock.

Systemd-dependent roles are tested in Docker by running containers in
privileged mode with cgroup mounts. The few things that truly cannot be tested
in Docker (kernel module loading, real hardware interaction) are handled by
the integration testing strategy (virsh VMs, see
[milestones.md](milestones.md#milestone-8-end-to-end-integration-testing-virsh-vms)).

---

## Standard `molecule.yml` Configuration

```yaml
# molecule/default/molecule.yml
driver:
  name: docker
platforms:
  - name: archlinux
    image: archlinux/archlinux:latest
    command: /usr/sbin/init
    tmpfs:
      - /run
      - /tmp
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
    cgroupns_mode: host
    privileged: true
    pre_build_image: true

  - name: ubuntu
    image: geerlingguy/docker-ubuntu2404-ansible:latest
    command: ""
    tmpfs:
      - /run
      - /tmp
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
    cgroupns_mode: host
    privileged: true
    pre_build_image: true

  - name: debian
    image: geerlingguy/docker-debian12-ansible:latest
    command: ""
    tmpfs:
      - /run
      - /tmp
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
    cgroupns_mode: host
    privileged: true
    pre_build_image: true

provisioner:
  name: ansible
verifier:
  name: ansible
```

---

## Arch Linux Container Image Choice

We use the **official `archlinux/archlinux:latest` image** rather than a
third-party image. The official image is rebuilt weekly and includes systemd
as part of the `base` meta package. It does **not** include Python.

**Why not a pre-built community image:** Community-maintained Arch images are
maintained by single individuals — `artis3n/docker-arch-ansible`, the most
prominent alternative, was archived in November 2025. The official Arch image
has no such risk.

**Contrast with Ubuntu/Debian:** Jeff Geerling's images are safe to depend
on — he has maintained them for years, they are the de facto community
standard, and they are used by thousands of roles.

---

## Arch `prepare.yml` for Python and sudo

The Arch container requires Python and sudo to be installed before Ansible can
run. Python is needed for module execution; sudo is needed for `become: true`.
The `ansible.builtin.raw` module does not require Python on the target:

```yaml
# molecule/default/prepare.yml
- hosts: archlinux
  gather_facts: false
  tasks:
    - name: Install Python, sudo, and openssh (Arch)
      ansible.builtin.raw: pacman -Syu --noconfirm python sudo openssh

    - name: Generate SSH host keys (Arch)
      ansible.builtin.raw: ssh-keygen -A

    - name: Start sshd (Arch)
      ansible.builtin.raw: systemctl start sshd
```

Debian/Ubuntu containers need an apt cache update, SSH preconditions, and
locale support in `prepare.yml`:

```yaml
- hosts: debian:ubuntu
  become: true
  tasks:
    - name: Update apt cache
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 600

    - name: Install prerequisite packages
      ansible.builtin.apt:
        name:
          - locales
          - openssh-server
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

### Why start sshd in prepare.yml?

Roles that deploy `/etc/ssh/sshd_config` with a `validate: sshd -t -f %s`
step and a handler that restarts sshd need the service **already running**
before converge. Without this, the handler fails because sshd was never
started. Previously this was masked with `failed_when: false` on the
handler — the correct fix is to start sshd in prepare.

---

## Precondition Handling

Because roles are standalone (no `meta/main.yml` dependencies), each role's
`prepare.yml` sets up minimal preconditions — the same way test fixtures
simulate external state.

```yaml
# molecule/default/prepare.yml for an extension role (e.g., syncthing_server)
- hosts: all
  become: true
  tasks:
    - name: Simulate base role - create service user
      ansible.builtin.user:
        name: testuser

    - name: Simulate server role - install expected packages
      ansible.builtin.package:
        name:
          - curl
          - rsync
        state: present
```

**What belongs in `prepare.yml`:** Only the specific preconditions the role
under test actually relies on — user accounts, directories, packages, config
files. This is deliberately minimal.

**What does NOT belong in `prepare.yml`:** The entire parent role's task
list. `prepare.yml` is a test fixture, not a role runner.

---

## Required Ansible Collections

CI workflows and the test-runner sidecar must have these collections
installed:

| Collection          | Why                                              |
| ------------------- | ------------------------------------------------ |
| `community.general` | `pacman` module for Arch package management       |
| `ansible.posix`     | `authorized_key` module for SSH key deployment    |

```bash
ansible-galaxy collection install community.general ansible.posix
```

---

## Vault-Encrypted Variables in Molecule Tests

Molecule tests use **plaintext values**, not vault-encrypted ones. There is
no `pass` or GPG setup in `prepare.yml`.

**Why:** Molecule tests validate role logic (does the user module set the
right password hash, does the template render correctly, etc.). The vault
decryption pipeline is an orthogonal concern — it operates at the
`ansible-pull` layer, not the role layer.

**What Molecule tests cover:**

- Plaintext `password_hash` values are correctly passed to the `user` module
- The `/etc/shadow` entry contains the expected hash format
- Omitted `password_hash` leaves the account locked

**What virsh integration tests cover (Milestone 8):**

- Full vault decryption pipeline via `--vault-id`
- Bootstrap with vault-encrypted inventory
- End-to-end: encrypted hash in inventory → decrypted by vault → set in shadow

---

## Inspecting Test Environments

- `molecule converge` — runs the playbook, leaves containers running
- `molecule login -h archlinux` — drops into a shell in the container
- `molecule destroy` — tears everything down
- Use `molecule converge` (not `molecule test`) during development to keep
  containers alive for debugging
